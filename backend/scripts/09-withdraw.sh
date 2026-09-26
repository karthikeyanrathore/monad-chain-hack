#!/usr/bin/env bash
# Withdraw MON from the contract back to the user's wallet. Usage: ./09-withdraw.sh [amount=0.05]
set -euo pipefail
source "$(dirname "$0")/config.sh"
need_user_key
need ME
TX=$(curl -s "$API/tx/withdraw" -H 'content-type: application/json' -d "{\"address\":\"$ME\",\"amount\":\"${1:-0.05}\"}")
echo "$TX" | jq -e .to >/dev/null || { echo "API error: $TX"; exit 1; }
cast send "$(echo "$TX" | jq -r .to)" "$(echo "$TX" | jq -r .data)" \
  --gas-limit "$(cast to-dec "$(echo "$TX" | jq -r .gas)")" --account "$USER_ACCOUNT" --rpc-url "$RPC" | grep -E '^status'
curl -s "$API/account/$ME"; echo
