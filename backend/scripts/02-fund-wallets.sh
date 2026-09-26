#!/usr/bin/env bash
# Send MON from deployer to the machine and user wallets. Usage: ./02-fund-wallets.sh [amount=0.5] [wallet ...]
# Wallets: verifier machine1 machine2 user (default: all that exist in wallets.env)
set -euo pipefail
source "$(dirname "$0")/config.sh"
AMOUNT="${1:-0.5}"; shift || true
NAMES=("$@"); [ ${#NAMES[@]} -gt 0 ] || NAMES=(verifier machine1 machine2 user)
for n in "${NAMES[@]}"; do
  case "$n" in verifier) a="$VERIFIER" ;; machine1) a="$MACHINE1" ;; machine2) a="$MACHINE2" ;; user) a="$ME" ;; *) echo "unknown wallet: $n"; exit 1 ;; esac
  [ -n "$a" ] || { echo "skip $n (no address in wallets.env)"; continue; }
  echo "$n <- $AMOUNT MON"
  cast send "$a" --value "${AMOUNT}ether" --account deployer --rpc-url "$RPC" | grep -E '^status'
  sleep 2  # Monad: wallets under 10 MON can send ~1 tx per 1.2 s
done
"$(dirname "$0")/07-balance.sh"
