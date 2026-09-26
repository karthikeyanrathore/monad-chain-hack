#!/usr/bin/env bash
# Send a signed, paid prompt, then show how much the deposit changed.
# Usage: ./08-prompt.sh "your prompt" [model=1B] [nonce=auto]
set -euo pipefail
source "$(dirname "$0")/config.sh"
need CONTRACT ME
PROMPT="${1:?usage: ./08-prompt.sh \"your prompt\" [1B|2B] [nonce]}"
MODEL="${2:-1B}"
NONCE="${3:-$(date +%s)}"   # new nonce every run

deposit() { cast call "$CONTRACT" 'balances(address)(uint256)' "$ME" --rpc-url "$RPC" | awk '{print $1}'; }

BEFORE=$(deposit)
SIG=$(cast wallet sign --account user "$(printf 'InferenceTruth request\nmodel: %s\nnonce: %s\nprompt: %s' "$MODEL" "$NONCE" "$PROMPT")")
BODY=$(jq -n --arg m "$MODEL" --arg p "$PROMPT" --argjson n "$NONCE" --arg s "$SIG" '{model:$m,prompt:$p,nonce:$n,signature:$s}')
curl -s "$API/infer" -H 'content-type: application/json' -d "$BODY" | jq .
AFTER=$(deposit)

echo "deposit before: $(cast from-wei "$BEFORE") MON"
echo "deposit after:  $(cast from-wei "$AFTER") MON"
echo "charged:        $(cast from-wei "$((BEFORE - AFTER))") MON"
