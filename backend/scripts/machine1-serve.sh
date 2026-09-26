#!/usr/bin/env bash
# Machine 1: serve llama3.2:1b through a public ngrok URL. Keep this running.
# The URL is saved to scripts/machine1.env, which 05-start-service.sh reads.
set -euo pipefail
source "$(dirname "$0")/config.sh"
MODEL="${MODEL_1B:-llama3.2:1b}"
PORT=11434

# 1. Ollama (start it only if it isn't already running)
if ! curl -sf "localhost:$PORT/api/version" >/dev/null; then
  ollama serve > "$ROOT/scripts/.ollama.log" 2>&1 &
  OLLAMA_PID=$!
  trap 'kill $OLLAMA_PID 2>/dev/null' EXIT
  until curl -sf "localhost:$PORT/api/version" >/dev/null; do sleep 1; done
fi
ollama pull "$MODEL" >/dev/null 2>&1 && echo "model ready: $MODEL"

# 2. ngrok tunnel. Ollama rejects unknown Host headers, so rewrite it to localhost.
ngrok http "$PORT" --host-header="localhost:$PORT" --log=stdout > "$ROOT/scripts/.ngrok.log" 2>&1 &
NGROK_PID=$!
trap 'kill $NGROK_PID ${OLLAMA_PID:-} 2>/dev/null' EXIT
URL=""
for _ in $(seq 1 30); do
  URL=$(curl -s localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url // empty' 2>/dev/null || true)
  [ -n "$URL" ] && break; sleep 1
done
[ -n "$URL" ] || { echo "ngrok did not start, see scripts/.ngrok.log"; exit 1; }

# 3. Save the URL and check the model answers through the tunnel
echo "MACHINE_1B_URL=$URL" > "$ROOT/scripts/machine1.env"
curl -sf "$URL/api/tags" | jq -e --arg m "$MODEL" '.models[] | select(.name == $m)' >/dev/null \
  && echo "Machine 1 serving $MODEL at $URL (saved to scripts/machine1.env)" \
  || { echo "tunnel is up but $MODEL is not reachable through it"; exit 1; }
wait $NGROK_PID
