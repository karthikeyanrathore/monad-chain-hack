"""Verification Service: re-runs a random sample of answered requests on an independent machine
running the same model, compares the two answers and settles the verdict on Monad.
PASS pays the provider's wallet (and the verifier's reward); FAIL refunds the user and slashes the provider."""

import asyncio
import difflib
import json
import logging
import os
import random
from pathlib import Path
from typing import Literal

import httpx
from eth_account import Account
from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from web3 import AsyncWeb3, Web3

log = logging.getLogger("verification-service")

SAMPLE_RATE = float(os.getenv("SAMPLE_RATE", "0.1"))  # share of requests re-checked
THRESHOLD = float(os.getenv("SIMILARITY_THRESHOLD", "0.75"))
# Only the opening of each answer is compared. The same model on different hardware drifts apart in
# long answers (measured: whole-answer similarity as low as 0.36 for honest machines), but the first
# 400 characters stay >= 0.86 for honest machines and <= 0.65 for a 1B/3B swap.
PREFIX_CHARS = int(os.getenv("PREFIX_CHARS", "400"))
VERIFY_TOKENS = int(os.getenv("VERIFY_TOKENS", "160"))  # enough tokens to cover the compared prefix
RETRIES = int(os.getenv("RETRIES", "10"))  # re-try the verifier machine if it is briefly down
RETRY_SECONDS = float(os.getenv("RETRY_SECONDS", "60"))
TIMEOUT = float(os.getenv("OLLAMA_TIMEOUT", "180"))
# Where each model size is re-run: a machine other than the provider, holding the same model.
VERIFY_URLS = {
    "1B": os.getenv("VERIFY_1B_URL", "http://localhost:11434"),
    "3B": os.getenv("VERIFY_3B_URL", "http://localhost:11434"),
}
GAS_BUFFER = 1.1  # Monad charges gas on the limit, not gas used

ABI = json.loads((Path(__file__).parent / "InferenceTruth.abi.json").read_text())
PENDING = 1  # InferenceTruth.Status.Pending


class Chain:
    def __init__(self, rpc_url: str, contract_address: str, verifier_key: str):
        self.w3 = AsyncWeb3(AsyncWeb3.AsyncHTTPProvider(rpc_url))
        self.contract = self.w3.eth.contract(address=Web3.to_checksum_address(contract_address), abi=ABI)
        self.account = Account.from_key(verifier_key)
        self._send_lock = asyncio.Lock()

    async def request(self, rid: bytes) -> tuple[int, bytes]:
        """(status, answerHash) of a recorded request."""
        r = await self.contract.functions.requests(rid).call()
        return r[5], r[6]

    async def submit_verdict(self, rid: bytes, passed: bool) -> str:
        fn = self.contract.functions.submitVerdict(rid, passed)
        async with self._send_lock:
            for attempt in range(3):  # low-balance Monad accounts are limited to ~1 tx per 1.2 s
                try:
                    tx = await fn.build_transaction({
                        "from": self.account.address,
                        "nonce": await self.w3.eth.get_transaction_count(self.account.address, "pending"),
                        "chainId": await self.w3.eth.chain_id,
                    })
                    tx["gas"] = int(tx["gas"] * GAS_BUFFER)
                    tx_hash = await self.w3.eth.send_raw_transaction(self.account.sign_transaction(tx).raw_transaction)
                    receipt = await self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
                    if receipt["status"] != 1:
                        raise RuntimeError(f"submitVerdict reverted: {tx_hash.to_0x_hex()}")
                    return tx_hash.to_0x_hex()
                except Exception:
                    if attempt == 2:
                        raise
                    await asyncio.sleep(2)


chain = (
    Chain(os.environ["RPC_URL"], os.environ["CONTRACT_ADDRESS"], os.environ["VERIFIER_PRIVATE_KEY"])
    if os.getenv("CONTRACT_ADDRESS")
    else None
)

app = FastAPI(title="Inference Truth · Verification Service")

# Let the dashboard (e.g. on Vercel) call this service from the browser.
# CORS_ORIGINS: comma-separated origins, default "*" for the demo.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",")],
    allow_methods=["GET", "POST"],
    allow_headers=["content-type"],
)

# request_id -> verdict record (in memory; enough for a demo)
verdicts: dict[str, dict] = {}


class VerifyRequest(BaseModel):
    request_id: str
    model: Literal["1B", "3B"]
    ollama_model: str
    prompt: str
    options: dict
    provider: str
    answer: str


def similarity(a: str, b: str) -> float:
    """Text similarity 0..1 of the answers' openings (first PREFIX_CHARS characters)."""
    return difflib.SequenceMatcher(None, a.strip()[:PREFIX_CHARS], b.strip()[:PREFIX_CHARS]).ratio()


async def generate_with_retry(v: dict, url: str, model: str, prompt: str, options: dict) -> str:
    """Re-run on the verifier machine, retrying while it is unreachable (e.g. its tunnel restarts)."""
    for attempt in range(RETRIES + 1):
        try:
            return await generate(url, model, prompt, options)
        except httpx.HTTPError as e:
            if attempt == RETRIES:
                raise
            v["reason"] = f"verifier machine unreachable, retry {attempt + 1}/{RETRIES}: {e}"
            await asyncio.sleep(RETRY_SECONDS)
    raise AssertionError("unreachable")


async def generate(url: str, model: str, prompt: str, options: dict) -> str:
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.post(
            f"{url}/api/generate", json={"model": model, "prompt": prompt, "stream": False, "options": options}
        )
        r.raise_for_status()
        return r.json()["response"]


async def verify(req: VerifyRequest) -> None:
    v = verdicts[req.request_id]
    rid = Web3.to_bytes(hexstr=req.request_id)
    try:
        if chain:
            status, onchain_hash = await chain.request(rid)
            if status != PENDING:
                v.update(status="skipped", reason="request is not pending on-chain")
                return
            if onchain_hash != Web3.keccak(text=req.answer):
                v.update(status="skipped", reason="answer does not match the hash recorded on-chain")
                return

        # Greedy decoding: generating fewer tokens gives the same opening, so the re-run can stop early.
        options = {**req.options, "num_predict": min(req.options.get("num_predict", VERIFY_TOKENS), VERIFY_TOKENS)}
        answer_b = await generate_with_retry(v, VERIFY_URLS[req.model], req.ollama_model, req.prompt, options)
        score = similarity(req.answer, answer_b)
        v.pop("reason", None)
        v.update(answer_b=answer_b, similarity=round(score, 3), passed=score >= THRESHOLD)
        if chain and (await chain.request(rid))[0] != PENDING:  # settled by someone else while retrying
            v.update(status="skipped", reason="request settled before the verdict")
            return
        if chain:
            v["tx_hash"] = await chain.submit_verdict(rid, v["passed"])
        v["status"] = "done"
    except Exception as e:
        log.warning("verification of %s failed: %s", req.request_id, e)
        v.update(status="error", reason=str(e))


async def machine_online(url: str) -> bool:
    try:
        async with httpx.AsyncClient(timeout=4) as client:
            return (await client.get(f"{url}/api/version")).status_code == 200
    except httpx.HTTPError:
        return False


@app.get("/health")
async def health():
    """Liveness, plus whether the verifier machine(s) that re-run requests are reachable."""
    urls = sorted(set(VERIFY_URLS.values()))
    online = await asyncio.gather(*(machine_online(u) for u in urls))
    return {"status": "ok", "onchain": chain is not None, "sample_rate": SAMPLE_RATE, "threshold": THRESHOLD,
            "prefix_chars": PREFIX_CHARS, "verifier_machine_online": all(online)}


@app.post("/verify", status_code=202)
async def verify_endpoint(req: VerifyRequest, background_tasks: BackgroundTasks):
    """Called by the Inference Service after each answer. Samples, then verifies in the background."""
    if req.request_id in verdicts:
        raise HTTPException(409, "request already received")
    sampled = random.random() < SAMPLE_RATE
    verdicts[req.request_id] = {
        "request_id": req.request_id,
        "model": req.model,
        "provider": req.provider,
        "sampled": sampled,
        "status": "pending" if sampled else "not_sampled",
    }
    if sampled:
        background_tasks.add_task(verify, req)
    return verdicts[req.request_id]


@app.get("/verdicts/{request_id}")
async def get_verdict(request_id: str):
    if request_id not in verdicts:
        raise HTTPException(404, "unknown request")
    return verdicts[request_id]
