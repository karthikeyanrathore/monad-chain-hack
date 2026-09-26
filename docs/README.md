# Inference Truth Docs

Decentralized AI inference on Monad. Machines run LLMs off-chain, a verifier spot-checks the answers, and Monad settles payment, rewards and slashing in MON.

| File | Contents |
|---|---|
| [01-platform-plan.md](01-platform-plan.md) | Overview, machine setup, decisions log, build phases, risks |
| [02-verification.md](02-verification.md) | How verification works, how to set the threshold, demo script |
| [03-phase-1.md](03-phase-1.md) | `InferenceTruth.sol` functions, economics, tests, deploy |
| [04-inference-truth-architecture.md](04-inference-truth-architecture.md) | Architecture components and step-by-step flow |
| [05-services.md](05-services.md) | Inference Service and Verification Service: the Inference Service routes to the chosen model and calls the Verification Service |
| [inference-truth-architecture.html](inference-truth-architecture.html) | Visual diagram (also published: https://claude.ai/artifact/2GcWK9QJNfnELiu5wqNGWY) |

**Setup:** Machine 1 runs 1B, Machine 2 runs 3B, and Machine 3 is the verifier with both models.
