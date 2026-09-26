#!/usr/bin/env bash
# Send MON from deployer to machine1 and user. Usage: ./02-fund-wallets.sh [amount=0.5]
set -euo pipefail
source "$(dirname "$0")/config.sh"
need MACHINE1 ME
AMOUNT="${1:-0.5}"
for a in "$MACHINE1" "$ME"; do
  cast send "$a" --value "${AMOUNT}ether" --account deployer --rpc-url "$RPC" | grep -E '^status'
  sleep 2  # Monad: wallets under 10 MON can send ~1 tx per 1.2 s
done
"$(dirname "$0")/07-balance.sh"
