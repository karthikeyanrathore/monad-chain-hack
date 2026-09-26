# Inference Service

The entry point of Inference Truth. It sends each prompt to the machine running the chosen model, returns the answer, then passes the request to the Verification Service in the background.

| Model | Machine | Where |
|---|---|---|
| 1B | Machine 1 | this laptop, `llama3.2:1b` |
| 2B | Machine 2 | external machine |
| — | Machine 3 | external machine, Verification Service |

The service calls each machine's **Ollama API** (`POST /api/generate`) directly, with fixed parameters `temperature 0, seed 42, num_predict 256` so the verifier can reproduce the answer.

## Run
```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env          # set Machine 2 and verifier addresses
set -a; source .env; set +a
.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000
```

On the external machines, Ollama must accept network connections:
```bash
OLLAMA_HOST=0.0.0.0 ollama serve
```

## Endpoints
| Method | Path | What it does |
|---|---|---|
| `POST` | `/infer` | Body: `{"model": "1B" \| "2B", "prompt": "...", "nonce": 1, "signature": "0x..."}`. Returns `{request_id, model, provider, answer, user, tx_hash}` |
| `GET` | `/models` | Lists 1B and 2B, whether each is configured, and `price_wei` |
| `GET` | `/account/{address}` | Deposited balance, wallet balance and stake (all in wei) |
| `POST` | `/tx/deposit` | Body: `{"address": "0x...", "amount": "1.5"}` (MON). Returns an **unsigned** `deposit()` transaction |
| `POST` | `/tx/withdraw` | Same body. Returns an **unsigned** `withdraw(amount)` transaction |
| `GET` | `/health` | Liveness check, plus whether on-chain mode is on |

## Paying with MON (on-chain mode)
The service never holds user keys. The user's own wallet signs everything.

1. **Deposit:** call `POST /tx/deposit`. Sign the returned transaction with your wallet and send it to Monad. Its fields are hex quantities, ready for `eth_sendTransaction`. The gas limit is the estimate plus 10%, because Monad charges for the gas limit.
2. **Prompt:** sign this exact text with `personal_sign` (EIP-191):
   ```
   InferenceTruth request
   model: 1B
   nonce: 1
   prompt: What is Monad?
   ```
   Then send `POST /infer` with the same `model`, `prompt`, `nonce` and the `signature`.
   - The signer's address pays the model price from their deposit.
   - Use a new nonce for every request. A reused nonce returns `409`.
3. **Withdraw:** call `POST /tx/withdraw`, then sign and send the returned transaction.

Without `CONTRACT_ADDRESS`, the service runs off-chain. `/infer` then needs no signature, and the `/account` and `/tx/*` endpoints return `503`.

Interactive API docs: `http://localhost:8000/docs`

```bash
curl -s localhost:8000/infer -H 'content-type: application/json' \
  -d '{"model":"1B","prompt":"What is Monad?"}'
```

**Errors:** a model with no machine configured returns `503`. A machine that can't be reached returns `502`. An unknown model or an empty prompt returns `422`.

## Call to the Verification Service
After answering, if `VERIFIER_URL` is set, the service sends `POST {VERIFIER_URL}/verify` with:
```json
{"request_id": "...", "model": "1B", "ollama_model": "llama3.2:1b", "prompt": "...",
 "options": {"temperature": 0, "seed": 42, "num_predict": 256},
 "provider": "machine-1", "answer": "..."}
```
If that call fails, the failure is logged. The user already has their answer, so it doesn't affect the response.

## Not yet included
- On-chain steps: the balance check and `recordRequest`. These will be added when `InferenceTruth.sol` exists.

## Tests
```bash
.venv/bin/pytest -q
```
