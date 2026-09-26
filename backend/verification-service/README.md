# Verification Service

This is Machine 3's role. The Inference Service calls it after every answer. It picks a random sample of requests and re-runs each one on an independent machine holding the same model. It compares the two answers and settles the result on Monad with `submitVerdict`:

| Verdict | On-chain effect |
|---|---|
| **PASS** (similarity ≥ threshold) | The price goes **straight to the provider's wallet**, minus 10%, which goes straight to the verifier's wallet |
| **FAIL** | The user's deposit is refunded, and 50% of the provider's stake is slashed to the owner |
| Not sampled | Nothing now. Anyone can call `settle()` after the challenge window, which pays the provider's wallet |

Before re-running, it checks that the request is still pending on-chain, and that the answer matches the hash the Inference Service recorded.

## Endpoints
| Method | Path | What it does |
|---|---|---|
| `POST` | `/verify` | Called by the Inference Service with `{request_id, model, ollama_model, prompt, options, provider, answer}`. Returns `202` |
| `GET` | `/verdicts/{request_id}` | `{sampled, status, passed, similarity, answer_b, tx_hash, reason}`. `status` is one of `pending`, `not_sampled`, `done`, `skipped`, `error` |
| `GET` | `/health` | Liveness check, plus sample rate and threshold |

## Config (env)
| Variable | Default | Meaning |
|---|---|---|
| `VERIFY_1B_URL`, `VERIFY_3B_URL` | `http://localhost:11434` | Ollama URL used to re-run each model size (Machine 3) |
| `SAMPLE_RATE` | `0.1` | Share of requests checked. `1` checks every request (demo) |
| `SIMILARITY_THRESHOLD` | `0.75` | Minimum similarity of the answers' openings for PASS |
| `PREFIX_CHARS` | `400` | How many opening characters are compared |
| `VERIFY_TOKENS` | `160` | Tokens the verifier generates (enough to cover the opening) |
| `RETRIES`, `RETRY_SECONDS` | `10`, `60` | Retry the verifier machine while it is unreachable |
| `RPC_URL`, `CONTRACT_ADDRESS`, `VERIFIER_PRIVATE_KEY` | – | On-chain mode. The key must be the contract's `verifier` |

Run it with `backend/scripts/05b-start-verifier.sh`, which reads Machine 3's URL from `scripts/machine3.env`.

## How reliable is the comparison?
The comparison measures how similar the texts are (`difflib`), not whether they mean the same thing. It compares only the **first 400 characters**, because the same model on different hardware drifts apart in long answers. Measured on the real machines (long prompts):

| Compared | Honest (same model), lowest | 1B/3B swap, highest |
|---|---|---|
| Whole answer (old) | **0.36**, which caused a false FAIL and slash | 0.40 |
| First 400 characters (now) | **0.86** | **0.65** |

With the threshold at 0.75, honest machines pass and swaps fail. On one-word answers ("Paris.") both models give the same text, so a swap there isn't caught.

## Tests
```bash
.venv/bin/pytest -q
```
