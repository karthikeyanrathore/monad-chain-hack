#!/usr/bin/env bash
# A provider machine stakes MON for its model. Usage: ./04-stake.sh [amount=0.2] [machine1|machine2]
# machine1 stakes for 1B, machine2 for 3B.
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT
AMOUNT="${1:-0.2}"; WALLET="${2:-machine1}"
case "$WALLET" in
  machine1) MODEL=1B; ADDR="$MACHINE1" ;;
  machine2) MODEL=3B; ADDR="$MACHINE2" ;;
  *) echo "usage: ./04-stake.sh [amount] [machine1|machine2]"; exit 1 ;;
esac
[ -n "$ADDR" ] || { echo "$WALLET has no address in wallets.env: run 01-create-wallets.sh"; exit 1; }
cast send "$CONTRACT" "stake(bytes32)" "$(cast format-bytes32-string $MODEL)" \
  --value "${AMOUNT}ether" --account "$WALLET" --rpc-url "$RPC" | grep -E '^status'
echo "$WALLET stake for $MODEL: $(cast from-wei "$(cast call "$CONTRACT" 'stakes(address)(uint256)' "$ADDR" --rpc-url "$RPC" | awk '{print $1}')") MON"
