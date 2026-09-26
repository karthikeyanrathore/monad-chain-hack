#!/usr/bin/env bash
# Hackathon demo: give the Inference Service (:8000) and Verification Service (:9000) public HTTPS URLs
# with Cloudflare quick tunnels (no account needed), so the dashboard on Vercel can reach them.
# Start 05b-start-verifier.sh and 05-start-service.sh first. Keep this running; Ctrl+C closes both tunnels.
# URLs change on every start: update the Vercel env vars and redeploy afterwards.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v cloudflared >/dev/null || { echo "missing cloudflared: brew install cloudflared"; exit 1; }

# Start both tunnels in this shell so Ctrl+C / exit closes them.
cloudflared tunnel --no-autoupdate --url http://localhost:8000 > "$DIR/.tunnel-8000.log" 2>&1 &
P1=$!
cloudflared tunnel --no-autoupdate --url http://localhost:9000 > "$DIR/.tunnel-9000.log" 2>&1 &
P2=$!
trap 'kill $P1 $P2 2>/dev/null || true' EXIT INT TERM

url_of() {  # $1 log file -> public URL once cloudflared reports it
  for _ in $(seq 1 30); do
    url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$1" | head -1 || true)
    [ -n "$url" ] && { echo "$url"; return 0; }
    sleep 1
  done
  return 1
}
BACKEND=$(url_of "$DIR/.tunnel-8000.log") || { echo "tunnel for :8000 did not start, see $DIR/.tunnel-8000.log"; exit 1; }
VERIFIER=$(url_of "$DIR/.tunnel-9000.log") || { echo "tunnel for :9000 did not start, see $DIR/.tunnel-9000.log"; exit 1; }
printf 'NEXT_PUBLIC_BACKEND_URL=%s\nNEXT_PUBLIC_VERIFIER_URL=%s\n' "$BACKEND" "$VERIFIER" > "$DIR/public.env"

sleep 3  # give the tunnels a moment to route
for pair in "Inference Service:$BACKEND" "Verification Service:$VERIFIER"; do
  name=${pair%%:*}; url=${pair#*:}
  if curl -sf -m 15 "$url/health" >/dev/null; then echo "OK    $name  $url"; else echo "DOWN  $name  $url  (is it running locally?)"; fi
done
echo
echo "Set these in Vercel (Project → Settings → Environment Variables), then redeploy:"
cat "$DIR/public.env"
echo "Also saved to backend/scripts/public.env. Ctrl+C to close the tunnels."
wait
