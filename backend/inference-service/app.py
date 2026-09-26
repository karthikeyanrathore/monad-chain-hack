"""Inference Service: routes a prompt to the machine running the chosen model,
returns the answer, records the paid request on Monad, and hands it to the Verification Service."""

import logging
import os
import secrets
from decimal import Decimal
from typing import Literal

import httpx
from fastapi import BackgroundTasks, FastAPI, HTTPException
from pydantic import BaseModel, Field
from web3 import Web3

import chain as chainlib

log = logging.getLogger("inference-service")

# Fixed generation parameters so the verifier can reproduce the answer.
GEN_OPTIONS = {"temperature": 0, "seed": 42, "num_predict": 256}

MACHINES = {
    "1B": {
        "provider": "machine-1",
        "url": os.getenv("MACHINE_1B_URL"),
        "model": os.getenv("MODEL_1B", "llama3.2:1b"),
        "address": os.getenv("PROVIDER_1B_ADDRESS"),
    },
    "3B": {
        "provider": "machine-2",
        "url": os.getenv("MACHINE_3B_URL"),
        "model": os.getenv("MODEL_3B", "llama3.2:3b"),
        "address": os.getenv("PROVIDER_3B_ADDRESS"),
    },
}
VERIFIER_URL = os.getenv("VERIFIER_URL")
TIMEOUT = float(os.getenv("OLLAMA_TIMEOUT", "120"))

# On-chain mode is on when a contract address is configured.
chain = (
    chainlib.Chain(os.environ["RPC_URL"], os.environ["CONTRACT_ADDRESS"], os.environ["SERVICE_PRIVATE_KEY"])
    if os.getenv("CONTRACT_ADDRESS")
    else None
)

app = FastAPI(title="Inference Truth · Inference Service")


class InferRequest(BaseModel):
    model: Literal["1B", "3B"]
    prompt: str = Field(min_length=1)
    nonce: int | None = Field(default=None, ge=0)
    signature: str | None = None


class InferResponse(BaseModel):
    request_id: str
    model: str
    provider: str
    answer: str
    user: str | None = None
    tx_hash: str | None = None


class AmountRequest(BaseModel):
    address: str
    amount: Decimal = Field(gt=0, description="Amount in MON")


async def generate(url: str, model: str, prompt: str) -> str:
    """Call a machine's Ollama API and return the generated text."""
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.post(
            f"{url}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False, "options": GEN_OPTIONS},
        )
        r.raise_for_status()
        return r.json()["response"]


async def send_to_verifier(payload: dict) -> None:
    """Hand the request to the Verification Service. Failures are logged, not raised,
    because the user already has their answer."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(f"{VERIFIER_URL}/verify", json=payload)
            r.raise_for_status()
    except httpx.HTTPError as e:
        log.warning("verification call failed for %s: %s", payload["request_id"], e)


def machine_down(size: str) -> HTTPException:
    """User-facing message when the machine serving a model can't answer."""
    name = MACHINES[size]["provider"].replace("machine-", "Machine ")
    return HTTPException(502, f"{name} running the llama {size} model is not up right now. Try again later or pick another model.")


def require_chain():
    if chain is None:
        raise HTTPException(503, "on-chain mode is not configured")
    return chain


def checksum(address: str) -> str:
    if not Web3.is_address(address):
        raise HTTPException(400, "invalid address")
    return Web3.to_checksum_address(address)


@app.get("/health")
async def health():
    return {"status": "ok", "onchain": chain is not None}


@app.get("/models")
async def models():
    result = []
    for size, m in MACHINES.items():
        item = {"model": size, "provider": m["provider"], "configured": bool(m["url"] and m["model"])}
        if chain:
            item["price_wei"] = str(await chain.price(size))
        result.append(item)
    return result


@app.get("/account/{address}")
async def account(address: str):
    return await require_chain().account_info(checksum(address))


@app.post("/tx/deposit")
async def deposit_tx(req: AmountRequest):
    """Unsigned deposit() transaction. The user's wallet signs and sends it."""
    try:
        return await require_chain().deposit_tx(checksum(req.address), Web3.to_wei(req.amount, "ether"))
    except chainlib.ChainError as e:
        raise HTTPException(400, f"cannot build deposit: {e}")


@app.post("/tx/withdraw")
async def withdraw_tx(req: AmountRequest):
    """Unsigned withdraw(amount) transaction. The user's wallet signs and sends it."""
    try:
        return await require_chain().withdraw_tx(checksum(req.address), Web3.to_wei(req.amount, "ether"))
    except chainlib.ChainError as e:
        raise HTTPException(400, f"cannot build withdraw: {e}")


@app.post("/infer", response_model=InferResponse)
async def infer(req: InferRequest, background_tasks: BackgroundTasks):
    machine = MACHINES[req.model]
    if not (machine["url"] and machine["model"]):
        log.warning("%s model has no machine configured", req.model)
        raise machine_down(req.model)

    user = None
    if chain:
        if req.nonce is None or not req.signature:
            raise HTTPException(400, "nonce and signature are required")
        if not machine["address"]:
            raise HTTPException(503, f"{req.model} provider address is not configured")
        try:
            user = chainlib.recover_user(req.model, req.nonce, req.prompt, req.signature)
        except Exception:
            raise HTTPException(401, "invalid signature")
        rid = chainlib.request_id(user, req.nonce)
        if await chain.request_exists(rid):
            raise HTTPException(409, "nonce already used")
        if await chain.deposited(user) < await chain.price(req.model):
            raise HTTPException(402, "deposited balance is below the model price")
    else:
        rid = secrets.token_bytes(32)

    try:
        answer = await generate(machine["url"], machine["model"], req.prompt)
    except httpx.HTTPError as e:
        log.warning("%s failed for %s: %s", machine["provider"], req.model, e)
        raise machine_down(req.model)

    tx_hash = None
    if chain:
        try:
            tx_hash = await chain.record_request(rid, user, machine["address"], req.model, chainlib.answer_hash(answer))
        except chainlib.ChainError as e:
            raise HTTPException(502, f"could not record request on-chain: {e}")

    request_id = "0x" + rid.hex()
    if VERIFIER_URL:
        background_tasks.add_task(send_to_verifier, {
            "request_id": request_id,
            "model": req.model,
            "ollama_model": machine["model"],
            "prompt": req.prompt,
            "options": GEN_OPTIONS,
            "provider": machine["provider"],
            "answer": answer,
        })

    return InferResponse(
        request_id=request_id, model=req.model, provider=machine["provider"], answer=answer, user=user, tx_hash=tx_hash
    )
