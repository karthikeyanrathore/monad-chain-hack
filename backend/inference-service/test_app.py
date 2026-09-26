import httpx
import pytest
from fastapi.testclient import TestClient

import app as service


@pytest.fixture
def client(monkeypatch):
    calls = {"generate": [], "verify": []}

    async def fake_generate(url, model, prompt):
        calls["generate"].append((url, model, prompt))
        return f"answer from {model}"

    async def fake_verify(payload):
        calls["verify"].append(payload)

    monkeypatch.setattr(service, "generate", fake_generate)
    monkeypatch.setattr(service, "send_to_verifier", fake_verify)
    monkeypatch.setitem(service.MACHINES["1B"], "url", "https://machine1.ngrok.app")
    monkeypatch.setitem(service.MACHINES, "3B", {"provider": "machine-2", "url": "http://m2:11434", "model": "llama3.2:3b"})
    monkeypatch.setattr(service, "VERIFIER_URL", "http://m3:9000")
    c = TestClient(service.app)
    c.calls = calls
    return c


def test_1b_routes_to_machine_1(client):
    r = client.post("/infer", json={"model": "1B", "prompt": "hi"})
    assert r.status_code == 200
    assert r.json()["provider"] == "machine-1"
    assert r.json()["answer"] == "answer from llama3.2:1b"
    assert client.calls["generate"] == [("https://machine1.ngrok.app", "llama3.2:1b", "hi")]


def test_3b_routes_to_machine_2(client):
    r = client.post("/infer", json={"model": "3B", "prompt": "hi"})
    assert r.status_code == 200
    assert r.json()["provider"] == "machine-2"
    assert client.calls["generate"] == [("http://m2:11434", "llama3.2:3b", "hi")]


def test_calls_verifier_with_request(client):
    r = client.post("/infer", json={"model": "1B", "prompt": "hi"})
    [payload] = client.calls["verify"]
    assert payload["request_id"] == r.json()["request_id"]
    assert payload["prompt"] == "hi"
    assert payload["answer"] == "answer from llama3.2:1b"
    assert payload["options"] == service.GEN_OPTIONS


def test_no_verifier_configured_skips_call(client, monkeypatch):
    monkeypatch.setattr(service, "VERIFIER_URL", None)
    client.post("/infer", json={"model": "1B", "prompt": "hi"})
    assert client.calls["verify"] == []


def test_unconfigured_model_says_machine_is_not_up(client, monkeypatch):
    monkeypatch.setitem(service.MACHINES, "3B", {"provider": "machine-2", "url": None, "model": None})
    r = client.post("/infer", json={"model": "3B", "prompt": "hi"})
    assert r.status_code == 502
    assert r.json()["detail"].startswith("Machine 2 running the llama 3B model is not up right now.")


def test_unknown_model_or_empty_prompt_rejected(client):
    assert client.post("/infer", json={"model": "70B", "prompt": "hi"}).status_code == 422
    assert client.post("/infer", json={"model": "1B", "prompt": ""}).status_code == 422


def test_machine_failure_returns_502(client, monkeypatch):
    async def broken(url, model, prompt):
        raise httpx.ConnectError("refused")

    monkeypatch.setattr(service, "generate", broken)
    r = client.post("/infer", json={"model": "1B", "prompt": "hi"})
    assert r.status_code == 502
    assert r.json()["detail"].startswith("Machine 1 running the llama 1B model is not up right now.")
    assert "refused" not in r.json()["detail"]  # no technical details for users
    assert client.calls["verify"] == []


# ---------------------------------------------------------------- on-chain mode

from eth_account import Account
from eth_account.messages import encode_defunct

import chain as chainlib

USER = Account.create()
PROVIDER_1B = "0x" + "11" * 20


def sign(model, nonce, prompt, account=USER):
    msg = encode_defunct(text=chainlib.request_message(model, nonce, prompt))
    return account.sign_message(msg).signature.to_0x_hex()


class FakeChain:
    def __init__(self):
        self.deposits = {USER.address: 10**18}
        self.used = set()
        self.recorded = []

    async def price(self, size):
        return 10**15

    async def deposited(self, address):
        return self.deposits.get(address, 0)

    async def request_exists(self, rid):
        return rid in self.used

    async def record_request(self, rid, user, provider, size, ahash):
        self.recorded.append((rid, user, provider, size, ahash))
        self.used.add(rid)
        return "0xabc"

    async def deposit_tx(self, sender, amount_wei):
        return {"from": sender, "value": hex(amount_wei)}


@pytest.fixture
def onchain(client, monkeypatch):
    fake = FakeChain()
    monkeypatch.setattr(service, "chain", fake)
    monkeypatch.setitem(service.MACHINES["1B"], "address", PROVIDER_1B)
    client.fake = fake
    return client


def test_signed_infer_records_request(onchain):
    r = onchain.post("/infer", json={"model": "1B", "prompt": "hi", "nonce": 1, "signature": sign("1B", 1, "hi")})
    assert r.status_code == 200
    body = r.json()
    assert body["user"] == USER.address
    assert body["tx_hash"] == "0xabc"
    [(rid, user, provider, size, ahash)] = onchain.fake.recorded
    assert rid == chainlib.request_id(USER.address, 1)
    assert body["request_id"] == "0x" + rid.hex()
    assert (user, provider, size) == (USER.address, PROVIDER_1B, "1B")
    assert ahash == chainlib.answer_hash("answer from llama3.2:1b")


def test_onchain_requires_signature(onchain):
    assert onchain.post("/infer", json={"model": "1B", "prompt": "hi"}).status_code == 400


def test_signature_for_other_prompt_charges_someone_else(onchain):
    # A signature over a different prompt recovers a different address with no deposit.
    r = onchain.post("/infer", json={"model": "1B", "prompt": "hi", "nonce": 1, "signature": sign("1B", 1, "other")})
    assert r.status_code == 402
    assert onchain.fake.recorded == []


def test_replayed_nonce_rejected(onchain):
    body = {"model": "1B", "prompt": "hi", "nonce": 7, "signature": sign("1B", 7, "hi")}
    assert onchain.post("/infer", json=body).status_code == 200
    assert onchain.post("/infer", json=body).status_code == 409


def test_insufficient_deposit_returns_402(onchain):
    poor = Account.create()
    r = onchain.post("/infer", json={"model": "1B", "prompt": "hi", "nonce": 1, "signature": sign("1B", 1, "hi", poor)})
    assert r.status_code == 402


def test_garbage_signature_returns_401(onchain):
    r = onchain.post("/infer", json={"model": "1B", "prompt": "hi", "nonce": 1, "signature": "0x1234"})
    assert r.status_code == 401


def test_deposit_tx_converts_mon_to_wei(onchain):
    r = onchain.post("/tx/deposit", json={"address": USER.address.lower(), "amount": "0.5"})
    assert r.status_code == 200
    assert r.json() == {"from": USER.address, "value": hex(5 * 10**17)}


def test_deposit_rejects_bad_input(onchain):
    assert onchain.post("/tx/deposit", json={"address": "nope", "amount": "1"}).status_code == 400
    assert onchain.post("/tx/deposit", json={"address": USER.address, "amount": "0"}).status_code == 422


def test_account_endpoints_need_chain(client):
    assert client.get(f"/account/{USER.address}").status_code == 503


def test_cors_allows_the_dashboard(client):
    r = client.options("/infer", headers={"Origin": "https://infermon.vercel.app", "Access-Control-Request-Method": "POST"})
    assert r.status_code == 200 and r.headers["access-control-allow-origin"] in ("*", "https://infermon.vercel.app")
