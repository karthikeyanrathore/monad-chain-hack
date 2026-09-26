#!/usr/bin/env bash
# Show wallet balances, plus what the contract holds for each wallet.
set -euo pipefail
source "$(dirname "$0")/config.sh"
need DEPLOYER MACHINE1 ME
mon() { cast from-wei "$(cast call "$CONTRACT" "$1" "$2" --rpc-url "$RPC" | awk '{print $1}')"; }
echo "WALLETS"
for pair in deployer:$DEPLOYER verifier:$VERIFIER machine1:$MACHINE1 machine2:$MACHINE2 user:$ME; do
  [ -n "${pair#*:}" ] || continue
  printf "  %-9s %s  %s MON\n" "${pair%%:*}" "${pair#*:}" "$(cast balance "${pair#*:}" --ether --rpc-url "$RPC")"
done
if [ -n "$CONTRACT" ]; then
  echo "CONTRACT $CONTRACT"
  echo "  user deposit:            $(mon 'balances(address)(uint256)' "$ME") MON"
  echo "  machine1 stake:          $(mon 'stakes(address)(uint256)' "$MACHINE1") MON"
  echo "  machine1 earnings:       $(mon 'balances(address)(uint256)' "$MACHINE1") MON"
  echo "  machine1 pending:        $(cast call "$CONTRACT" 'pendingCount(address)(uint256)' "$MACHINE1" --rpc-url "$RPC") requests"
  if [ -n "$MACHINE2" ]; then
    echo "  machine2 stake:          $(mon 'stakes(address)(uint256)' "$MACHINE2") MON"
    echo "  machine2 earnings:       $(mon 'balances(address)(uint256)' "$MACHINE2") MON"
  fi
  echo "  deployer credited:       $(mon 'balances(address)(uint256)' "$DEPLOYER") MON  (verifier rewards + slashed stakes)"
fi
