# 05 · Services: Inference and Verification

The **Inference Service** is the entry point. It calls the model the user chose, then calls the **Verification Service** itself. The Verification Service re-checks a random sample and settles the verdict on Monad.

```
User ──prompt + model (1B/3B)──▶ INFERENCE SERVICE
                                   │ 1. route by chosen model
                                   │      1B ──▶ Machine 1 (1B)
                                   │      3B ──▶ Machine 2 (3B)
                                   │ 2. Answer A ──▶ user
                                   │ 3. recordRequest(requestId, answerHash) ──▶ InferenceTruth.sol
                                   │ 4. POST /verify ─────────┐
                                   ▼                          ▼
                                            VERIFICATION SERVICE (Machine 3)
                                              sample ~1 in 10
                                              re-run on Machine 3 (same model) ──▶ Answer B
                                              compare A vs B ──▶ PASS / FAIL
                                              submitVerdict(requestId, pass) ──▶ InferenceTruth.sol
```

## 1. Inference Service
**Job:** take the user's prompt, call the chosen model, return the answer, then hand the request to verification.

| | |
|---|---|
| Runs on | Any host (e.g. a separate laptop, or Machine 1) |
| Wallet | Inference Service key, the only address allowed to call `recordRequest` |
| Calls | Machine 1 or Machine 2 (`/generate`), `InferenceTruth.sol`, Verification Service (`/verify`) |

**`POST /infer`**
- Request: `{ user, model: "1B" | "3B", prompt, signature }`
- Response: `{ requestId, answer, provider }`
- Steps:
  1. Verify the user's signature and check their on-chain balance against the model price.
  2. **Route by the chosen model:** `1B → Machine 1`, `3B → Machine 2`.
  3. Call the machine's Ollama API with fixed parameters (`temperature 0, seed 42, num_predict 256`) and get **Answer A**.
  4. Call `recordRequest(requestId, user, provider, modelId, keccak256(answerA))` on-chain. This locks the price in escrow.
  5. Return Answer A to the user.
  6. **Call the Verification Service:** `POST /verify { requestId, model, prompt, params, answerA, provider }`.
     - The call is asynchronous, so the user never waits for verification.

## 2. Verification Service
**Job:** decide whether to check the request, re-run it, compare the answers, and send the verdict on-chain.

| | |
|---|---|
| Runs on | Machine 3, which holds both the 1B and 3B models |
| Wallet | Verifier key, the only address allowed to call `submitVerdict` |
| Called by | Inference Service (`/verify`) |
| Calls | Its local 1B/3B model, `InferenceTruth.sol` |

**`POST /verify`**
- Request: `{ requestId, model, prompt, params, answerA, provider }`
- Response: `202 Accepted` right away. The work runs in the background.
- Steps:
  1. **Sample:** the Verification Service picks about 1 in 10 at random.
     - The Inference Service sends *every* request, so it can't choose which ones get checked.
     - Requests that aren't sampled are settled later by `settle(requestId)` after the challenge window.
  2. **Integrity check:** confirm that `keccak256(answerA)` equals the `answerHash` recorded on-chain. A mismatch counts as a FAIL.
  3. **Re-run** the same prompt, model and parameters on Machine 3's local model to get **Answer B**.
  4. **Compare** the answers with semantic similarity plus text overlap against a threshold (see [02-verification.md](02-verification.md)).
  5. **Settle:** call `submitVerdict(requestId, pass)`.
     - **PASS:** the provider is paid and the verifier is rewarded.
     - **FAIL:** the provider's stake is slashed and the user is refunded.

**`GET /verdicts/{requestId}`** returns `{ sampled, pass, similarity, txHash }` for the frontend and the demo.

## 3. Machines (Ollama)
Each machine runs **Ollama**, and the services call its API (`POST /api/generate`) directly, so no extra node service is needed.
- **Machine 1:** this laptop, running `llama3.2:1b`.
- **Machine 2:** external, running the 3B model.
- **Machine 3:** external, running both models plus the Verification Service.

The external machines must start Ollama with `OLLAMA_HOST=0.0.0.0` so they accept network connections.

## Why this split
- **Simple flow:** there's one entry point, and the Inference Service drives everything.
- **Fast answers:** the user gets Answer A before verification runs.
- **Independent verdicts:** only the Verification Service's key can call `submitVerdict`. The Verification Service does its own sampling and checks the on-chain hash, so the Inference Service can't pick which requests get checked or alter Answer A.

## Build order
1. Ollama on all three machines. **Check:** the same prompt at temperature 0 gives near-identical text on the provider and on Machine 3.
2. Inference Service `/infer` with routing and `recordRequest`. **Check:** a 1B prompt is answered by Machine 1, a 3B prompt by Machine 2, and a `RequestRecorded` event appears on the explorer.
3. Verification Service `/verify` with `submitVerdict`, called from the Inference Service. **Check:**
   - An honest request leads to a PASS transaction.
   - When Machine 2 runs in cheat mode, a request leads to a FAIL transaction and a `Slashed` event.

## Implementation status
- **Inference Service:** built in [`backend/inference-service/`](../backend/inference-service/README.md).
  - Endpoints: `POST /infer`, `GET /models`, `GET /health`.
  - Calls the Verification Service's `/verify` when `VERIFIER_URL` is set.
  - On-chain mode: user deposits and withdrawals through unsigned transactions (`/tx/deposit`, `/tx/withdraw`), `/account/{address}`, signed `/infer`, and `recordRequest` after each answer.
- **Contract:** `InferenceTruth.sol` in [`backend/contracts/`](../backend/contracts/README.md), with 18 Foundry tests. Deployed to Monad testnet at `0x144e60D7084aBc1253A60aA6451cA2c48e7fc024` (1B and 3B).
- **Verification Service:** built in [`backend/verification-service/`](../backend/verification-service/README.md). Re-runs on Machine 3; PASS pays the provider wallet directly.
