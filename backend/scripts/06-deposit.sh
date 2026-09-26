#!/usr/bin/env bash
# Deposit MON into the contract as the user. Usage: ./06-deposit.sh [amount=0.1]
set -euo pipefail
source "$(dirname "$0")/config.sh"
need_user_key
need ME
TX=$(curl -s "$API/tx/deposit" -H 'content-type: application/json' -d "{\"address\":\"$ME\",\"amount\":\"${1:-0.1}\"}")
echo "$TX" | jq -e .to >/dev/null || { echo "API error: $TX"; exit 1; }
cast send "$(echo "$TX" | jq -r .to)" "$(echo "$TX" | jq -r .data)" \
  --value "$(cast to-dec "$(echo "$TX" | jq -r .value)")" --gas-limit "$(cast to-dec "$(echo "$TX" | jq -r .gas)")" \
  --account "$USER_ACCOUNT" --rpc-url "$RPC" | grep -E '^status'
curl -s "$API/account/$ME"; echo
