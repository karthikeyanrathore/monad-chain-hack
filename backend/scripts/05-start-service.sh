#!/usr/bin/env bash
# Start the Inference Service in on-chain mode. It signs recordRequest with the deployer wallet (asks its password).
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT DEPLOYER MACHINE1 MACHINE_1B_URL

ROLE=$(cast call "$CONTRACT" 'inferenceService()(address)' --rpc-url "$RPC")
[ "$ROLE" = "$DEPLOYER" ] || { echo "Contract's Inference Service is $ROLE, not deployer. Run: cast send $CONTRACT 'setRoles(address,address)' $DEPLOYER $DEPLOYER --account deployer --rpc-url $RPC"; exit 1; }
curl -sf -m 10 "$MACHINE_1B_URL/api/version" >/dev/null || { echo "Machine 1 not reachable at $MACHINE_1B_URL: start machine1-serve.sh"; exit 1; }
# Machine 2 (3B) is optional: without its URL and staked wallet, 3B requests fail.
if [ -n "$MACHINE_3B_URL" ]; then
  curl -sf -m 10 "$MACHINE_3B_URL/api/version" >/dev/null || echo "warning: Machine 2 not reachable at $MACHINE_3B_URL (3B requests will fail)"
  [ -n "$MACHINE2" ] || echo "warning: no machine2 wallet (run 01-create-wallets.sh, then 04-stake.sh 0.2 machine2) - 3B requests will fail"
fi

cd "$ROOT/inference-service"
RPC_URL="$RPC" CONTRACT_ADDRESS="$CONTRACT" PROVIDER_1B_ADDRESS="$MACHINE1" MACHINE_1B_URL="$MACHINE_1B_URL" \
MACHINE_3B_URL="$MACHINE_3B_URL" MODEL_3B="$MODEL_3B" PROVIDER_3B_ADDRESS="$MACHINE2" \
VERIFIER_URL="${VERIFIER_URL:-http://localhost:9000}" VERIFIER_MACHINE_URL="${VERIFY_1B_URL:-}" \
SERVICE_PRIVATE_KEY="$(cast wallet decrypt-keystore deployer | awk '{print $NF}')" \
exec .venv/bin/uvicorn app:app --port 8000
