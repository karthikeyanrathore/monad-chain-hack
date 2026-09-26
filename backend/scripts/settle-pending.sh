#!/usr/bin/env bash
# Pay out requests that never got a verdict (e.g. the verifier machine was down): after the challenge
# window, settle() sends the full price to the provider's wallet. Anyone may call it; by default the
# machine1 wallet sends the transactions (asks its password). Usage: ./settle-pending.sh [wallet=machine1]
# DRY_RUN=1 ./settle-pending.sh lists what would be settled without sending anything.
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT DEPLOYER
ACCOUNT="${1:-machine1}"
if [ -n "${DRY_RUN:-}" ]; then KEY=0x$(printf '1%.0s' {1..64}); else KEY="$(cast wallet decrypt-keystore "$ACCOUNT" | awk '{print $NF}')"; fi
cd "$ROOT/verification-service"
RPC="$RPC" CONTRACT="$CONTRACT" DEPLOYER="$DEPLOYER" KEY="$KEY" .venv/bin/python - <<'PY'
import json, os, time
from eth_account import Account
from web3 import Web3

w3 = Web3(Web3.HTTPProvider(os.environ["RPC"]))
C = Web3.to_checksum_address(os.environ["CONTRACT"]); D = Web3.to_checksum_address(os.environ["DEPLOYER"])
c = w3.eth.contract(address=C, abi=json.load(open("InferenceTruth.abi.json")))
me = Account.from_key(os.environ["KEY"])
SEL = Web3.keccak(text="recordRequest(bytes32,address,address,bytes32,bytes32)")[:4].hex().removeprefix("0x")
window = c.functions.challengeWindow().call()

# Every request was recorded by the Inference Service (deployer): walk its transactions by nonce.
latest = w3.eth.block_number; n = w3.eth.get_transaction_count(D, latest)
def first_block(k, lo, hi):
    while lo < hi:
        mid = (lo + hi) // 2
        if w3.eth.get_transaction_count(D, mid) >= k: hi = mid
        else: lo = mid + 1
    return lo
lo = max(0, latest - 200000)

pending = []
for k in range(max(1, n - int(os.getenv("LOOKBACK", "100"))), n + 1):  # the deployer's recent transactions
    b = first_block(k, lo, latest); lo = b
    if w3.eth.get_transaction_count(D, b - 1) >= k: continue
    for tx in w3.eth.get_block(b, full_transactions=True).transactions:
        data = tx.input.hex().removeprefix("0x")
        if tx["from"] == D and tx.to == C and data.startswith(SEL):
            rid = bytes.fromhex(data[8:72])
            r = c.functions.requests(rid).call()
            if r[5] == 1:  # Pending
                pending.append((rid, r[1], r[3], r[4]))

now = w3.eth.get_block("latest").timestamp
print(f"{len(pending)} pending request(s)")
for rid, provider, price, created in pending:
    if now < created + window:
        print(f"  0x{rid.hex()[:10]}… window open for {created + window - now}s more, skipped"); continue
    if os.getenv("DRY_RUN"):
        print(f"  0x{rid.hex()[:10]}… would settle: {price/1e18} MON -> {provider}"); continue
    tx = c.functions.settle(rid).build_transaction({
        "from": me.address, "nonce": w3.eth.get_transaction_count(me.address, "pending"), "chainId": w3.eth.chain_id})
    tx["gas"] = int(tx["gas"] * 1.1)  # Monad charges the gas limit
    h = w3.eth.send_raw_transaction(me.sign_transaction(tx).raw_transaction)
    ok = w3.eth.wait_for_transaction_receipt(h, timeout=60).status
    print(f"  0x{rid.hex()[:10]}… settled={bool(ok)}: {price/1e18} MON -> {provider}  tx {h.to_0x_hex()}")
    time.sleep(2)  # Monad: wallets under 10 MON can send ~1 tx per 1.2 s
PY
