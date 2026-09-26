import pytest
from fastapi.testclient import TestClient
from web3 import Web3

import app as service

RID = "0x" + "ab" * 32


def body(answer="Paris.", rid=RID):
    return {
        "request_id": rid,
        "model": "3B",
        "ollama_model": "llama3.2:3b",
        "prompt": "Capital of France?",
        "options": {"temperature": 0, "seed": 42, "num_predict": 256},
        "provider": "machine-2",
        "answer": answer,
    }


class FakeChain:
    def __init__(self, status=1, answer="Paris."):
        self.status = status
        self.hash = Web3.keccak(text=answer)
        self.verdicts = []

    async def request(self, rid):
        return self.status, self.hash

    async def submit_verdict(self, rid, passed):
        self.verdicts.append((rid, passed))
        return "0xverdict"


@pytest.fixture
def client(monkeypatch):
    calls = []

    async def fake_generate(url, model, prompt, options):
        calls.append((url, model, prompt, options))
        return "Paris."

    monkeypatch.setattr(service, "generate", fake_generate)
    monkeypatch.setattr(service, "SAMPLE_RATE", 1.0)
    monkeypatch.setattr(service, "chain", FakeChain())
    monkeypatch.setitem(service.VERIFY_URLS, "3B", "http://verifier:11434")
    service.verdicts.clear()
    c = TestClient(service.app)
    c.calls = calls
    return c


def test_matching_answer_passes_and_submits_verdict(client):
    r = client.post("/verify", json=body())
    assert r.status_code == 202
    v = client.get(f"/verdicts/{RID}").json()
    assert v["status"] == "done" and v["passed"] is True and v["similarity"] == 1.0
    assert v["tx_hash"] == "0xverdict"
    assert service.chain.verdicts == [(Web3.to_bytes(hexstr=RID), True)]
    # re-run on the verifier machine with the same model; only enough tokens for the compared opening
    assert client.calls == [
        ("http://verifier:11434", "llama3.2:3b", "Capital of France?", {**body()["options"], "num_predict": service.VERIFY_TOKENS})
    ]


def test_different_answer_fails(client, monkeypatch):
    monkeypatch.setattr(service, "chain", FakeChain(answer="Berlin is the capital of Germany."))
    client.post("/verify", json=body(answer="Berlin is the capital of Germany."))
    v = client.get(f"/verdicts/{RID}").json()
    assert v["passed"] is False
    assert service.chain.verdicts == [(Web3.to_bytes(hexstr=RID), False)]


def test_not_sampled_is_not_checked(client, monkeypatch):
    monkeypatch.setattr(service, "SAMPLE_RATE", 0.0)
    r = client.post("/verify", json=body())
    assert r.json()["status"] == "not_sampled"
    assert client.calls == [] and service.chain.verdicts == []


def test_answer_not_matching_onchain_hash_is_skipped(client):
    client.post("/verify", json=body(answer="something else"))
    v = client.get(f"/verdicts/{RID}").json()
    assert v["status"] == "skipped"
    assert client.calls == [] and service.chain.verdicts == []


def test_request_not_pending_is_skipped(client, monkeypatch):
    monkeypatch.setattr(service, "chain", FakeChain(status=4))
    client.post("/verify", json=body())
    assert client.get(f"/verdicts/{RID}").json()["status"] == "skipped"


def test_duplicate_and_unknown(client):
    assert client.post("/verify", json=body()).status_code == 202
    assert client.post("/verify", json=body()).status_code == 409
    assert client.get("/verdicts/0x00").status_code == 404


def test_only_the_opening_is_compared(client, monkeypatch):
    opening = "Newton's third law says every action has an equal and opposite reaction. " * 6  # > 400 chars
    honest_a = opening + "For example, a rocket pushes gas down and the gas pushes the rocket up."
    honest_b = opening + "Walking works because your foot pushes the ground back and the ground pushes you forward."

    async def other_ending(*a):
        return honest_b

    monkeypatch.setattr(service, "generate", other_ending)
    monkeypatch.setattr(service, "chain", FakeChain(answer=honest_a))
    client.post("/verify", json=body(answer=honest_a))
    v = client.get(f"/verdicts/{RID}").json()
    assert v["passed"] is True and v["similarity"] == 1.0


def test_retries_until_verifier_machine_is_back(client, monkeypatch):
    attempts = []

    async def flaky(*a):
        attempts.append(1)
        if len(attempts) < 3:
            raise service.httpx.ConnectError("tunnel offline")
        return "Paris."

    monkeypatch.setattr(service, "generate", flaky)
    monkeypatch.setattr(service, "RETRY_SECONDS", 0)
    client.post("/verify", json=body())
    v = client.get(f"/verdicts/{RID}").json()
    assert len(attempts) == 3 and v["status"] == "done" and v["passed"] is True and "reason" not in v


def test_model_failure_is_recorded_as_error(client, monkeypatch):
    async def broken(*a):
        raise RuntimeError("verifier machine down")

    monkeypatch.setattr(service, "generate", broken)
    client.post("/verify", json=body())
    v = client.get(f"/verdicts/{RID}").json()
    assert v["status"] == "error" and "verifier machine down" in v["reason"]
    assert service.chain.verdicts == []


def test_health_reports_verifier_machine(client, monkeypatch):
    async def down(url):
        return False

    monkeypatch.setattr(service, "machine_online", down)
    assert client.get("/health").json()["verifier_machine_online"] is False
