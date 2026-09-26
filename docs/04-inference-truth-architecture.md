# 04 · Inference Truth: Decentralized AI Inference on Monad

- **Visual diagram:** [inference-truth-architecture.html](inference-truth-architecture.html)
- **Published artifact (private):** https://claude.ai/artifact/2GcWK9QJNfnELiu5wqNGWY

## Main flow
```
User / AI Agent → Inference Service → chosen model (Machine 1 or 2) → Inference Service calls Verification Service → PASS/FAIL → Monad Smart Contract → Payment / Reward / Slashing
```

## Components

The off-chain part runs as two services. The **Inference Service** is the entry point: it calls the model the user chose, then calls the **Verification Service**. See [05-services.md](05-services.md).

### Off-chain (AI compute)
- **User / AI Agent:** submits a prompt, **picks a model size (1B or 3B)**, pays in MON, receives the final answer.
- **Machines:** each runs its LLM locally as an independent node:
  | Machine | Model | Role |
  |---|---|---|
  | Machine 1 | 1B | Provider: serves 1B requests |
  | Machine 2 | 3B | Provider: serves 3B requests |
  | Machine 3 | 1B + 3B | Verifier: re-runs sampled requests |
- **Inference Service (entry point):**
  1. Receives the prompt and the chosen model.
  2. Calls the matching machine: 1B → Machine 1, 3B → Machine 2. That machine returns **Answer A**.
  3. Returns Answer A to the user and records the request on-chain (`recordRequest`, with a hash of Answer A).
  4. Calls the **Verification Service** with the request.
- **Verification Service (on Machine 3, called by the Inference Service):**
  1. A random subset of requests is selected (e.g. 1 in 10).
  2. The same prompt, **same model size** and parameters are re-run on **Machine 3 (verifier)**, which has both models, and it returns **Answer B**.
  3. Answer A and Answer B are compared by semantic similarity against a threshold (e.g. 0.85).
  4. **PASS ✓** if the answers match, **FAIL ✗** if they diverge.
  5. Sends the verdict on-chain with `submitVerdict`.

### On-chain (Monad Testnet: economics and settlement only; no LLM runs here)
- **MON Payments / Escrow:** price depends on model size. The user's MON is locked per request, released on PASS and refunded on FAIL. Every transaction pays gas in MON.
- **Provider Staking:** all three machines stake MON as collateral (Machine 1: 1B, Machine 2: 3B, Machine 3: verifier with 1B + 3B).
- **`InferenceTruth.sol`:** `deposit()`, `stake()`, `recordRequest()`, `submitVerdict()`, `settle()`. Full spec: [03-phase-1.md](03-phase-1.md).
- **Reward (PASS):** the provider is paid in MON and the verifier earns a reward.
- **Slash (FAIL):** the provider's stake is slashed automatically and the user is refunded.

## Step by step
1. **Prompt + pay:** the user or agent sends a prompt, picks 1B or 3B and locks MON in escrow.
2. **Route:** the Inference Service calls Machine 1 for 1B or Machine 2 for 3B.
3. **Answer:** that machine's local LLM returns Answer A. The Inference Service sends it to the user and records the request on-chain.
4. **Verify:** the Inference Service calls the Verification Service. A random sample is re-run on Machine 3 with the same model to get Answer B.
5. **Compare:** semantic similarity decides PASS or FAIL.
6. **Settle on Monad:** the Verification Service sends the verdict transaction to `InferenceTruth.sol`.
7. **Pay or slash:** PASS pays the provider and verifier. FAIL slashes the stake.

## Design note: verifying with different model sizes
A 1B answer and a 3B answer to the same prompt naturally differ, so the verifier must use the **same** model the user paid for. That's why Machine 3 holds both the 1B and the 3B model:
- For a 1B request, Machine 3 runs 1B.
- For a 3B request, it runs 3B.

**Tradeoff:** Machine 3 is a single verifier. If it goes offline or cheats, verification stops or is compromised. A later version could add more verifiers, or use stored reference fingerprints per model (see [02-verification.md](02-verification.md)).
