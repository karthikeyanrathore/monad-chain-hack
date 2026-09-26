# 03 · Phase 1: `InferenceTruth.sol`

Phase 1 is only the smart contract, with no frontend or LLMs yet. It's the on-chain economic layer: MON escrow, staking, verdicts, payments, rewards and slashing.

## Roles
| Role | Who | Model |
|---|---|---|
| Provider | Machine 1 | 1B |
| Provider | Machine 2 | 2B |
| Verifier | Machine 3 | 1B + 2B |
| Inference Service | Inference Service key | routes requests to the chosen model, calls `recordRequest`, then calls the Verification Service |
| User | Wallet | pays in MON |

## Contract functions
**Setup (admin)**
- `addModel(modelId, price)`: registers `1B` and `2B` with their prices in MON.

**Machines**
- `stake(modelId, role)` is payable. A machine locks MON as collateral and registers as provider or verifier.
- `unstake()`: withdraw the stake after a cooldown, if nothing is pending.

**Users**
- `deposit()` is payable, and `withdraw(amount)` returns unused MON.

**Per request (Inference Service only)**
- `recordRequest(requestId, user, provider, modelId, answerHash)`: locks the model's price from the user's balance in escrow.

**Verification Service (Machine 3) only**
- `submitVerdict(requestId, pass)`:
  - **PASS:** the provider is paid and the verifier gets a reward.
  - **FAIL:** the provider's stake is slashed and the user is refunded.

**Settlement**
- `settle(requestId)`: requests that weren't sampled pay the provider once the challenge window ends.

## Default economics (adjust later)
| Item | Default |
|---|---|
| Verifier reward | 10% of the request price, taken only on PASS |
| Slash on FAIL | a fixed share of the provider's stake (e.g. 50%) |
| Where slashed MON goes | refund to the user; the remainder to the verifier or treasury |
| Challenge window | N blocks before an unsampled request can be settled |

## Events
`Deposited`, `Staked`, `RequestRecorded`, `VerdictSubmitted`, `Paid`, `Rewarded`, `Slashed`, `Refunded`. The frontend and the demo read these events.

## Foundry tests
- Deposit and withdraw work, and a user can't withdraw more than their balance.
- `recordRequest` fails if the user's balance is below the model price.
- A machine without a stake can't be recorded as a provider.
- PASS: the provider and verifier balances increase by the right amounts.
- FAIL: the stake is slashed, and the user is refunded.
- Only the verifier can call `submitVerdict`, and only once per request.
- `settle` fails before the window ends and pays the provider after it.
- `unstake` is blocked while requests are pending.

## Deploy
Deploy to Monad testnet with `forge script`. Save the contract address for Phases 2 to 4.

**Monad gas note:** gas is billed on the gas *limit*, not gas used, so set tight limits on `recordRequest` and `submitVerdict`.

## Done when
- All tests pass.
- The contract is live on Monad testnet.
- A deposit, a stake and a PASS/FAIL verdict all show up on the explorer.

## Tools
Solidity and Foundry (`forge test`, `forge script`), plus testnet wallets for the user and each of the three machines, funded from the Monad faucet.
