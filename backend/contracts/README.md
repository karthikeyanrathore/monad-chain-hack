# InferenceTruth contract

`src/InferenceTruth.sol` is the on-chain settlement layer on Monad. It handles MON deposits, provider staking, request escrow, verdicts (PASS pays, FAIL slashes and refunds) and settlement.

| Function | Caller | What it does |
|---|---|---|
| `deposit()` payable | user | Adds MON to the user's balance |
| `withdraw(amount)` | anyone | Withdraws credited MON: user deposits, provider earnings, verifier rewards |
| `stake(modelId)` payable | provider machine | Locks collateral and registers the model it serves |
| `unstake()` | provider machine | Returns the stake when no requests are pending |
| `recordRequest(requestId, user, provider, modelId, answerHash)` | Inference Service | Locks the model price from the user's balance |
| `submitVerdict(requestId, pass)` | Verification Service | PASS pays the provider and gives the verifier 10%. FAIL refunds the user and slashes 50% of the provider's stake to the owner |
| `settle(requestId)` | anyone | Pays the provider once the challenge window passes without a verdict |
| `setModelPrice`, `setRoles` | owner | Admin. Initial prices are set in the constructor, so deploying is one transaction |

Model IDs are `bytes32` strings: `cast format-bytes32-string 1B`.

## Setup and test
```bash
forge install --no-git foundry-rs/forge-std@v1.16.2 OpenZeppelin/openzeppelin-contracts@v5.7.0   # lib/ is not committed
forge test
```

## Deploy to Monad testnet (chain 10143)
```bash
export INFERENCE_SERVICE=0x...   # Inference Service wallet
export VERIFIER=0x...            # Machine 3 wallet
forge script script/Deploy.s.sol --rpc-url monad_testnet --broadcast --account deployer \
  --sender $(cast wallet address --account deployer) --gas-estimate-multiplier 110
```
Defaults (override with env): `MIN_STAKE` 0.1 MON, `CHALLENGE_WINDOW` 600 s, `PRICE_1B` 0.001 MON, `PRICE_3B` 0.003 MON, `VERIFIER_REWARD_BPS` 1000, `SLASH_BPS` 5000.

Each provider machine then stakes:
```bash
cast send <CONTRACT> "stake(bytes32)" $(cast format-bytes32-string 1B) --value 0.2ether --rpc-url monad_testnet --account <machine-keystore>
```

## Trust assumptions (hackathon scope)
- **Charging:** the Inference Service decides who gets charged. It only charges users who signed the request, but the contract itself doesn't check that signature.
- **Verdicts:** the verifier is a single trusted address.
