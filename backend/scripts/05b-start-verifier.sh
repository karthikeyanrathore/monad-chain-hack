#!/usr/bin/env bash
# Start the Verification Service (Machine 3 role) on port 9000. It signs submitVerdict with the
# verifier wallet (asks its password). PASS sends MON straight to the provider's wallet.
# Each model is re-run on Machine 3, which holds both llama3.2:1b and llama3.2:3b.
# Its URL comes from scripts/machine3.env (VERIFY_1B_URL / VERIFY_3B_URL). SAMPLE_RATE=1 checks every request (demo); use 0.1 normally.
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT VERIFIER
ROLE=$(cast call "$CONTRACT" 'verifier()(address)' --rpc-url "$RPC")
[ "$ROLE" = "$VERIFIER" ] || { echo "Contract's verifier is $ROLE, not the verifier wallet ($VERIFIER). Redeploy with ./03-deploy.sh --force"; exit 1; }
V1="${VERIFY_1B_URL:?set VERIFY_1B_URL in scripts/machine3.env}"
V3="${VERIFY_3B_URL:?set VERIFY_3B_URL in scripts/machine3.env}"
for u in "$V1" "$V3"; do curl -sf -m 10 "$u/api/version" >/dev/null || echo "warning: $u not reachable"; done
echo "Re-running 1B on $V1, 3B on $V3, sample rate ${SAMPLE_RATE:-1}"
cd "$ROOT/verification-service"
RPC_URL="$RPC" CONTRACT_ADDRESS="$CONTRACT" VERIFY_1B_URL="$V1" VERIFY_3B_URL="$V3" SAMPLE_RATE="${SAMPLE_RATE:-1}" \
VERIFIER_PRIVATE_KEY="$(cast wallet decrypt-keystore verifier | awk '{print $NF}')" \
exec .venv/bin/uvicorn app:app --port 9000
