#!/usr/bin/env bash
# Show the verdict for a request id (printed by 08-prompt.sh). Usage: ./11-verdict.sh 0x<request_id>
set -euo pipefail
source "$(dirname "$0")/config.sh"
curl -s "${VERIFIER_URL:-http://localhost:9000}/verdicts/${1:?usage: ./11-verdict.sh 0x<request_id>}" | jq .
