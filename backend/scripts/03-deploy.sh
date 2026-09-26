#!/usr/bin/env bash
# Deploy InferenceTruth to Monad testnet and save the address to scripts/deployed.env.
# deployer becomes owner, Inference Service and (for now) verifier.
# Usage: ./03-deploy.sh [--force]   (--force replaces an existing deployment)
set -euo pipefail
source "$(dirname "$0")/config.sh"
need DEPLOYER
if [ -n "$CONTRACT" ] && [ "${1:-}" != "--force" ]; then
  echo "Already deployed at $CONTRACT. Run with --force to deploy a new contract."; exit 1
fi
cd "$ROOT/contracts"
OUT=$(INFERENCE_SERVICE="$DEPLOYER" VERIFIER="$DEPLOYER" forge script script/Deploy.s.sol \
  --rpc-url "$RPC" --broadcast --account deployer --sender "$DEPLOYER" --gas-estimate-multiplier 110 | tee /dev/stderr)
ADDR=$(echo "$OUT" | grep 'deployed at' | awk '{print $NF}')
[ -n "$ADDR" ] || { echo "deploy failed"; exit 1; }
echo "CONTRACT=$ADDR" > "$ROOT/scripts/deployed.env"
echo "Saved CONTRACT=$ADDR"
