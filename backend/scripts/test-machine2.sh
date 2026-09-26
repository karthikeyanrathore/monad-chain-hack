#!/usr/bin/env bash
# Test Machine 2 (3B) end to end. Usage: ./test-machine2.sh [--paid]
#   checks 1-4: Machine 2 directly (no wallet needed)
#   check 5:    the Inference Service sees 3B
#   --paid:     also send a signed, paid 3B prompt through the service (asks the user password)
set -euo pipefail
source "$(dirname "$0")/config.sh"
URL="${MACHINE_3B_URL:?set MACHINE_3B_URL in scripts/machine2.env}"
MODEL="$MODEL_3B"
FAILED=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; FAILED=1; }
gen()  { curl -sf -m 120 "$URL/api/generate" -d "{\"model\":\"$MODEL\",\"prompt\":\"$1\",\"stream\":false,\"options\":{\"temperature\":0,\"seed\":42,\"num_predict\":64}}" | jq -r .response; }

echo "Machine 2: $URL ($MODEL)"

# 1. Reachable
if V=$(curl -sf -m 15 "$URL/api/version" | jq -r .version); then ok "reachable (ollama $V)"
else
  BODY=$(curl -s -m 15 "$URL/api/version" || true)
  if echo "$BODY" | grep -q ERR_NGROK_3200; then bad "tunnel offline: start ./serve-models.sh 3B on Machine 2"
  else bad "not reachable (a 403 means ngrok was started without --host-header; use serve-models.sh)"; fi
  exit 1
fi

# 2. Model installed
MODELS=$(curl -sf -m 15 "$URL/api/tags" | jq -r '.models[].name' | tr '\n' ' ')
if echo " $MODELS" | grep -q " $MODEL "; then ok "$MODEL installed"
else bad "$MODEL missing (has: $MODELS). On Machine 2 run: ./serve-models.sh 3B"; exit 1; fi

# 3. Generates an answer
START=$(date +%s)
A1=$(gen "What is the capital of France? Answer in one word.") || A1=""
if [ -n "$A1" ]; then ok "answer in $(( $(date +%s) - START ))s: $A1"; else bad "no answer from $MODEL"; fi

# 4. Deterministic (the verifier relies on this)
A2=$(gen "What is the capital of France? Answer in one word.") || A2=""
[ -n "$A1" ] && [ "$A1" = "$A2" ] && ok "same answer twice (temperature 0, seed 42)" || bad "answers differ: '$A1' vs '$A2'"

# 5. Inference Service knows 3B
if S=$(curl -sf -m 5 "$API/models"); then
  echo "$S" | jq -e '.[] | select(.model=="3B" and .configured)' >/dev/null \
    && ok "Inference Service has 3B configured" || bad "Inference Service does not have 3B: restart 05-start-service.sh"
else
  echo "  SKIP  Inference Service not running at $API"
fi

# Optional: paid 3B prompt through the whole system
if [ "${1:-}" = "--paid" ]; then
  echo "Paid 3B prompt:"
  "$(dirname "$0")/08-prompt.sh" "What is the capital of France? Answer in one word." 3B
fi

[ $FAILED -eq 0 ] && echo "Machine 2: all checks passed" || { echo "Machine 2: some checks failed"; exit 1; }
