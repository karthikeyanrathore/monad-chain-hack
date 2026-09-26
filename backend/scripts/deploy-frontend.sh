#!/usr/bin/env bash
# Deploy the InferMON dashboard to Vercel, pointed at the public backend URLs from expose-backend.sh.
# One time: npx vercel login. Rerun this after every expose-backend.sh restart (the tunnel URLs change).
set -euo pipefail
source "$(dirname "$0")/config.sh"
[ -f "$ROOT/scripts/public.env" ] || { echo "No public URLs yet: start ./expose-backend.sh first"; exit 1; }
source "$ROOT/scripts/public.env"
for u in "$NEXT_PUBLIC_BACKEND_URL" "$NEXT_PUBLIC_VERIFIER_URL"; do
  curl -sf -m 15 "$u/health" >/dev/null || { echo "$u is not reachable: is expose-backend.sh running?"; exit 1; }
done
cd "$ROOT/../frontend"
# NEXT_PUBLIC_* values are baked in at build time, so they are passed as build env.
npx --yes vercel deploy --prod --yes \
  --build-env NEXT_PUBLIC_BACKEND_URL="$NEXT_PUBLIC_BACKEND_URL" \
  --build-env NEXT_PUBLIC_VERIFIER_URL="$NEXT_PUBLIC_VERIFIER_URL" \
  --build-env NEXT_PUBLIC_USER_ADDRESS="${LOCK_TO_ADDRESS:-}"   # any wallet; set LOCK_TO_ADDRESS to restrict
