# 01 · Platform Plan: Inference Truth

**Inference Truth** is decentralized AI inference on Monad.
- Users pay in MON, pick a model size and send a prompt.
- Independent machines run the LLMs locally.
- A verifier machine spot-checks a random sample of answers.
- A Monad smart contract pays honest machines and slashes cheaters.

Full architecture: [04-inference-truth-architecture.md](04-inference-truth-architecture.md) · Diagram: [inference-truth-architecture.html](inference-truth-architecture.html)

## Current setup
| Machine | Model | Role |
|---|---|---|
| Machine 1 | 1B | Provider: serves 1B requests |
| Machine 2 | 2B | Provider: serves 2B requests |
| Machine 3 | 1B + 2B | Verifier: re-runs sampled requests |

## Main flow
```
User / AI Agent → Inference Service → chosen model machine (Answer A) → Inference Service calls Verification Service (Answer B) → PASS/FAIL
      → InferenceTruth.sol on Monad → Payment + reward  |  Slash + refund
```

## Off-chain vs on-chain
- **Off-chain:** two services. The **Inference Service** calls the model the user chose, then calls the **Verification Service**, which re-runs a sample and compares the answers. Monad never runs the LLM.
- **On-chain (Monad Testnet):** MON escrow, provider staking, verdicts, payments, rewards and slashing. Every transaction pays gas in MON.

## Decisions log
| Topic | Earlier idea | Current decision | Why |
|---|---|---|---|
| Where models run | AWS Lambda agents + GPU nodes | Local LLMs on 3 machines | Lambda has no GPU. Local machines are free and demo-friendly. |
| Model sizes | 7B / 13B / 70B | 1B and 2B | They fit on ordinary laptops. |
| Verification | TEE attestation | Re-run on the verifier and compare answers | TEE is too heavy for a hackathon. |
| Verifier | Any other provider | Machine 3, which holds both models | Verification needs the *same* model the user paid for. |

## Build phases
1. **Smart contract:** `InferenceTruth.sol`, Foundry tests, deploy to Monad testnet. See [03-phase-1.md](03-phase-1.md).
2. **Machine nodes:** a `/generate` endpoint on each machine wrapping its local LLM, run at fixed parameters (temperature 0, fixed seed).
3. **Two services** (see [05-services.md](05-services.md)):
   - **Inference Service:** routes 1B → Machine 1 and 2B → Machine 2, returns Answer A, calls `recordRequest` on-chain, then calls the Verification Service.
   - **Verification Service** (on Machine 3): called by the Inference Service. It samples about 1 in 10 requests, re-runs them to get Answer B, compares the answers, and calls `submitVerdict`.
4. **Frontend:** wallet connect, deposit MON, pick 1B or 2B, send a prompt, see the answer and the settlement.
5. **Demo:** a cheating provider gets caught and slashed live on the Monad explorer.

## Known risks
- **Single verifier:** if Machine 3 is offline, nothing gets verified. If it's dishonest, it can fail honest providers. Later: add more verifiers, or check against stored reference fingerprints ([02-verification.md](02-verification.md)).
- **Answers can vary across hardware** even with the same model and parameters. The threshold must be measured, not guessed.
