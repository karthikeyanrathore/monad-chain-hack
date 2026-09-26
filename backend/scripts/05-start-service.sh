#!/usr/bin/env bash
# Start the Inference Service in on-chain mode. It signs recordRequest with the deployer wallet (asks its password).
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT DEPLOYER MACHINE1 MACHINE_1B_URL

ROLE=$(cast call "$CONTRACT" 'inferenceService()(address)' --rpc-url "$RPC")
[ "$ROLE" = "$DEPLOYER" ] || { echo "Contract's Inference Service is $ROLE, not deployer. Run: cast send $CONTRACT 'setRoles(address,address)' $DEPLOYER $DEPLOYER --account deployer --rpc-url $RPC"; exit 1; }
curl -sf -m 10 "$MACHINE_1B_URL/api/version" >/dev/null || { echo "Machine 1 not reachable at $MACHINE_1B_URL: start machine1-serve.sh"; exit 1; }

cd "$ROOT/inference-service"
RPC_URL="$RPC" CONTRACT_ADDRESS="$CONTRACT" PROVIDER_1B_ADDRESS="$MACHINE1" MACHINE_1B_URL="$MACHINE_1B_URL" \
SERVICE_PRIVATE_KEY="$(cast wallet decrypt-keystore deployer | awk '{print $NF}')" \
exec .venv/bin/uvicorn app:app --port 8000
