#!/usr/bin/env bash
# Undo a wrong slash: the deployer withdraws the slashed MON credited to it in the contract and
# sends it back to the provider's wallet. Usage: ./refund-slash.sh [machine1|machine2] [amount=all credited]
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT DEPLOYER
case "${1:-machine1}" in machine1) TO="$MACHINE1" ;; machine2) TO="$MACHINE2" ;; *) echo "usage: ./refund-slash.sh [machine1|machine2] [amount]"; exit 1 ;; esac
CREDIT=$(cast call "$CONTRACT" 'balances(address)(uint256)' "$DEPLOYER" --rpc-url "$RPC" | awk '{print $1}')
AMOUNT="${2:+$(cast to-wei "$2")}"; AMOUNT="${AMOUNT:-$CREDIT}"
[ "$AMOUNT" -gt 0 ] && [ "$AMOUNT" -le "$CREDIT" ] || { echo "deployer has $(cast from-wei "$CREDIT") MON credited; nothing to refund"; exit 1; }
echo "Refunding $(cast from-wei "$AMOUNT") MON to ${1:-machine1} ($TO)"
cast send "$CONTRACT" "withdraw(uint256)" "$AMOUNT" --account deployer --rpc-url "$RPC" | grep -E '^status'
sleep 2  # Monad: wallets under 10 MON can send ~1 tx per 1.2 s
cast send "$TO" --value "$AMOUNT" --account deployer --rpc-url "$RPC" | grep -E '^status'
echo "Done. To restore the stake: ./04-stake.sh $(cast from-wei "$AMOUNT") ${1:-machine1}"
