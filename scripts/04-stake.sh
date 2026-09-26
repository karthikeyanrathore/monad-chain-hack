#!/usr/bin/env bash
# Machine 1 stakes MON for the 1B model. Usage: ./04-stake.sh [amount=0.2]
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT MACHINE1
cast send "$CONTRACT" "stake(bytes32)" "$(cast format-bytes32-string 1B)" \
  --value "${1:-0.2}ether" --account machine1 --rpc-url "$RPC" | grep -E '^status'
echo "machine1 stake: $(cast call "$CONTRACT" 'stakes(address)(uint256)' "$MACHINE1" --rpc-url "$RPC")"
