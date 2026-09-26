# 02 · Verification

**Goal:** catch a provider machine that doesn't honestly run the model the user paid for. For example, it might serve a cheaper model, return a cached or fake answer, or skip inference.
**Decision:** no TEE attestation. A verifier machine re-runs a random sample of requests, and the contract settles the result on-chain.

## How a check works
1. The provider (Machine 1 for 1B, Machine 2 for 3B) returns **Answer A** to the user.
2. The Inference Service calls the Verification Service with the request, and the Verification Service randomly samples it (e.g. 1 in 10).
   - Sampling happens *after* the answer is delivered, so a provider can't tell which requests will be checked.
3. The same prompt, model and parameters (temperature 0, fixed seed, same max tokens) are sent to **Machine 3**, which holds both the 1B and 3B models. It returns **Answer B**.
4. The service compares A and B:
   - **Semantic similarity:** cosine similarity of sentence embeddings.
   - **Text overlap as a second signal:** exact match or token overlap. The same model at temperature 0 should produce nearly identical text.
5. **PASS ✓** if the score is at or above the threshold, **FAIL ✗** if it's below.
6. Machine 3 sends `submitVerdict(requestId, pass)` to `InferenceTruth.sol` on Monad.

## Economic result (on-chain)
| Outcome | What happens |
|---|---|
| Not sampled | The provider is paid from escrow after the challenge window |
| PASS | The provider is paid, and the verifier earns a reward in MON |
| FAIL | The provider's stake is slashed automatically, and the user is refunded |

## Why the verifier needs both models
A 1B answer and a 3B answer to the same prompt naturally differ. Comparing across sizes would fail honest providers. So Machine 3 re-runs each request with the **same** model the user picked.

## Setting the threshold
Don't guess the threshold. Measure it:
1. **Honest pairs:** run 50 prompts on a provider and on Machine 3 with the same model and parameters. Record the similarity.
2. **Cheat pairs:** have the 3B provider secretly answer with 1B, then compare against Machine 3's 3B answer. Record the similarity.
3. **Pass condition:** the two sets of scores must not overlap. Set the threshold between them.
   - If they overlap, rely more on the text-overlap signal.
   - Or add a check on the output probabilities (below).

**Caution:** 1B and 3B models can give similar-*meaning* answers to easy prompts. Include harder prompts (reasoning, long answers) so a model swap shows up.

## Optional stronger check: output probabilities
Ask both machines for top-5 logprobs (the probability of each generated token) and compare them with KL divergence.
- The same model gives near-zero KL.
- A different model gives a large KL.

This is harder to fake than text similarity. Use it if the similarity test in "Setting the threshold" doesn't separate cleanly.

## Demo script
1. Run honest requests. Sampled checks pass, and provider and verifier payments appear on the Monad explorer.
2. Switch Machine 2 to "cheat mode", which answers 3B requests with 1B.
3. A sampled check fails, the `Slashed` event appears on-chain, and the user sees the refund.

## Limits
- **Single verifier (Machine 3):** it's a single point of failure and must be trusted. Later: several verifiers voting, or reference fingerprints stored on-chain.
- **Sampling rate:** with 1 in 10 sampling, a cheater is caught on about 10% of cheated requests. The slashing penalty must outweigh what a cheater gains on the other 90%.
- **Nondeterminism across hardware:** can cause small text differences. That's why a threshold is used instead of an exact match.
