# Trustless AI Inference on Monad

**Inference Truth** is decentralized AI inference on Monad:
- Users pay in MON and pick a model (1B or 2B).
- Independent machines run the LLMs locally.
- A verifier machine spot-checks a random sample of answers.
- The `InferenceTruth` contract pays honest machines and slashes cheaters.

| Folder | What's inside |
|---|---|
| [`contracts/`](contracts/README.md) | `InferenceTruth.sol` (Foundry): deposits, staking, escrow, verdicts, slashing |
| [`inference-service/`](inference-service/README.md) | FastAPI entry point: routes prompts to the chosen model, handles MON deposits, records requests on-chain |
| [`frontend/`](frontend/README.md) | Next.js chat UI |
| [`docs/`](docs/README.md) | Plan, architecture, verification design, service specs |

| Machine | Model | Role |
|---|---|---|
| Machine 1 (this laptop) | `llama3.2:1b` | Provider for 1B requests |
| Machine 2 (external) | 2B model | Provider for 2B requests |
| Machine 3 (external) | 1B + 2B | Verification Service (not built yet) |

## Prerequisites
- [Foundry](https://getfoundry.sh) (`forge`, `cast`, `anvil`)
- [Ollama](https://ollama.com) with `ollama pull llama3.2:1b`
- Python 3 and `jq`

Set up once:
```bash
(cd contracts && forge install --no-git foundry-rs/forge-std@v1.16.2 OpenZeppelin/openzeppelin-contracts@v5.7.0)
(cd inference-service && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt)
```

## Run on Monad testnet
Chain ID `10143`, RPC `https://testnet-rpc.monad.xyz`, faucet https://testnet.monad.xyz, explorer https://testnet.monadvision.com

### Quick way: step scripts
The scripts save what they create and read it back automatically: wallet addresses in `scripts/wallets.env`, Machine 1's ngrok URL in `scripts/machine1.env`, and the contract address in `scripts/deployed.env`.
```bash
cd scripts
./01-create-wallets.sh           # one time: deployer, machine1, user (saves addresses)
./02-fund-wallets.sh 0.5         # deployer sends MON to machine1 and user (fund deployer from the faucet first)
./03-deploy.sh                   # deploy InferenceTruth (refuses if already deployed; --force for a new one)
./04-stake.sh 0.2                # machine1 stakes for 1B
./machine1-serve.sh              # Machine 1: Ollama behind a public ngrok URL (keep running)
./05-start-service.sh            # Inference Service, calls Machine 1 via that URL (keep running)
./06-deposit.sh 0.1              # user deposits MON
./07-balance.sh                  # wallet balances + deposit, stake, earnings, pending requests
./08-prompt.sh "What is 2+2?"    # signed paid prompt (auto nonce), shows the amount charged
./09-withdraw.sh 0.05            # user withdraws MON
```

### Manual way: step by step

**1. Create wallets** (one time; each asks for a password)
```bash
for n in deployer machine1 user; do cast wallet new $n -p; done
cast wallet list    # should show all three
```
Save the addresses (each command asks for that wallet's password):
```bash
export DEPLOYER=$(cast wallet address --account deployer)
export MACHINE1=$(cast wallet address --account machine1)
export ME=$(cast wallet address --account user)
echo $DEPLOYER $MACHINE1 $ME
```
**2. Fund them** from the faucet: deployer ~2 MON (it deploys and pays gas for every prompt); machine1 and user ~0.5 MON each.
> Monad keeps a 10 MON reserve per wallet. A wallet below 10 MON can send only about 1 transaction every 1.2 s. If a transaction reverts, wait a second and retry.

**3. Deploy the contract** (one transaction: the prices are set in the constructor)
```bash
export RPC=https://testnet-rpc.monad.xyz
cd contracts
INFERENCE_SERVICE=$DEPLOYER VERIFIER=$DEPLOYER forge script script/Deploy.s.sol \
  --rpc-url $RPC --broadcast --account deployer --sender $DEPLOYER --gas-estimate-multiplier 110
export CONTRACT=0x...   # the "InferenceTruth deployed at" address printed above
```
The deployer also acts as the Inference Service (it signs `recordRequest`) and as the verifier until Machine 3 exists. Later, give the verifier role to Machine 3 with `setRoles(deployer, machine3)`.

**4. Machine 1 stakes for the 1B model**
```bash
cast send $CONTRACT "stake(bytes32)" $(cast format-bytes32-string 1B) --value 0.2ether --account machine1 --rpc-url $RPC
```

**5. Start the Inference Service** (uses the local Ollama `llama3.2:1b`)
```bash
cd ../inference-service
RPC_URL=$RPC CONTRACT_ADDRESS=$CONTRACT \
SERVICE_PRIVATE_KEY=$(cast wallet decrypt-keystore deployer | awk '{print $NF}') \
PROVIDER_1B_ADDRESS=$MACHINE1 .venv/bin/uvicorn app:app --port 8000
```

**6. Act as a user** (new terminal)
```bash
export RPC=https://testnet-rpc.monad.xyz
export ME=0x...   # user address from step 1

# deposit 0.1 MON: the API builds the tx, your wallet signs and sends it
TX=$(curl -s localhost:8000/tx/deposit -H 'content-type: application/json' -d "{\"address\":\"$ME\",\"amount\":\"0.1\"}")
cast send $(echo $TX | jq -r .to) $(echo $TX | jq -r .data) --value $(cast to-dec $(echo $TX | jq -r .value)) \
  --gas-limit $(cast to-dec $(echo $TX | jq -r .gas)) --account user --rpc-url $RPC

curl -s localhost:8000/account/$ME                                  # deposited_wei = 100000000000000000

# signed prompt (new NONCE each time)
PROMPT="What is 2+2?"; NONCE=1
SIG=$(cast wallet sign --account user "$(printf 'InferenceTruth request\nmodel: 1B\nnonce: %s\nprompt: %s' $NONCE "$PROMPT")")
curl -s localhost:8000/infer -H 'content-type: application/json' \
  -d "{\"model\":\"1B\",\"prompt\":\"$PROMPT\",\"nonce\":$NONCE,\"signature\":\"$SIG\"}"

curl -s localhost:8000/account/$ME                                  # drops by 0.001 MON
```
**Expected results**
- `/infer` returns the answer and a `tx_hash`. Open `https://testnet.monadvision.com/tx/<tx_hash>` to see `recordRequest` on-chain.
- Sending the same `NONCE` again returns `nonce already used` (409).

**Withdraw** the rest of the deposit:
```bash
TX=$(curl -s localhost:8000/tx/withdraw -H 'content-type: application/json' -d "{\"address\":\"$ME\",\"amount\":\"0.05\"}")
cast send $(echo $TX | jq -r .to) $(echo $TX | jq -r .data) --gas-limit $(cast to-dec $(echo $TX | jq -r .gas)) --account user --rpc-url $RPC
```

## Tests
```bash
(cd contracts && forge test)                     # 18 contract tests
(cd inference-service && .venv/bin/pytest -q)     # 16 service tests
```
API docs: http://localhost:8000/docs

## Status
- **Done:**
  - The contract and its tests.
  - The Inference Service: routing, deposits and withdrawals, signed paid requests, `recordRequest`.
- **Next:**
  - The Verification Service on Machine 3.
  