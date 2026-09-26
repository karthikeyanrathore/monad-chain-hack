#!/usr/bin/env bash
# Standalone: serve Ollama models through a public ngrok URL. Copy this file to any machine.
#
# Usage:
#   ./serve-models.sh 1B          # Machine 1: llama3.2:1b
#   ./serve-models.sh 3B          # Machine 2: llama3.2:3b
#   ./serve-models.sh 1B 3B       # Machine 3 (verifier): both
#
# Optional env:
#   MODEL_1B=llama3.2:1b  MODEL_3B=llama3.2:3b model names to pull and serve
#   NGROK_URL=my-name.ngrok-free.dev           reuse a fixed ngrok domain (from the ngrok dashboard)
#   PORT=11434                                 Ollama port
#   SAVE_TO=file SAVE_KEY=NAME                 also write NAME=<public url> to file
#
# Needs: ollama, ngrok (with `ngrok config add-authtoken <token>` done once), curl, jq.
set -euo pipefail

MODEL_1B="${MODEL_1B:-llama3.2:1b}"
MODEL_3B="${MODEL_3B:-llama3.2:3b}"
PORT="${PORT:-11434}"
[ $# -gt 0 ] || { sed -n '4,7p' "$0"; exit 1; }

for tool in ollama ngrok curl jq; do
  command -v "$tool" >/dev/null || { echo "missing: $tool"; exit 1; }
done

MODELS=()
for size in "$@"; do
  case "$size" in
    1B) MODELS+=("$MODEL_1B") ;;
    3B) MODELS+=("$MODEL_3B") ;;
    *) echo "unknown size: $size (use 1B and/or 3B)"; exit 1 ;;
  esac
done

PIDS=()
cleanup() { [ ${#PIDS[@]} -gt 0 ] && kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# 1. Ollama: reuse a running server, or start one
if ! curl -sf "localhost:$PORT/api/version" >/dev/null; then
  echo "starting ollama on port $PORT"
  OLLAMA_HOST="127.0.0.1:$PORT" ollama serve > ollama.log 2>&1 &
  PIDS+=($!)
  for _ in $(seq 1 30); do curl -sf "localhost:$PORT/api/version" >/dev/null && break; sleep 1; done
  curl -sf "localhost:$PORT/api/version" >/dev/null || { echo "ollama did not start, see ollama.log"; exit 1; }
fi

# 2. Pull each model and load it once so the first real request is fast
for m in "${MODELS[@]}"; do
  echo "pulling $m ..."
  ollama pull "$m" >/dev/null 2>&1 || { echo "could not pull $m"; exit 1; }
  curl -sf "localhost:$PORT/api/generate" -d "{\"model\":\"$m\",\"prompt\":\"hi\",\"stream\":false,\"options\":{\"num_predict\":1}}" >/dev/null \
    && echo "ready: $m" || { echo "$m failed to load"; exit 1; }
done

# 3. ngrok tunnel. Ollama rejects unknown Host headers, so rewrite it to localhost.
NGROK_ARGS=(http "$PORT" --host-header="localhost:$PORT" --log=stdout)
[ -n "${NGROK_URL:-}" ] && NGROK_ARGS+=(--url="$NGROK_URL")
ngrok "${NGROK_ARGS[@]}" > ngrok.log 2>&1 &
NGROK_PID=$!
PIDS+=($NGROK_PID)

URL=""
for _ in $(seq 1 30); do
  URL=$(curl -s localhost:4040/api/tunnels 2>/dev/null \
        | jq -r --arg p "$PORT" '.tunnels[] | select(.config.addr | endswith(":" + $p)) | .public_url' 2>/dev/null | head -1 || true)
  [ -n "$URL" ] && break
  kill -0 "$NGROK_PID" 2>/dev/null || { echo "ngrok exited, see ngrok.log"; tail -5 ngrok.log; exit 1; }
  sleep 1
done
[ -n "$URL" ] || { echo "ngrok did not report a URL, see ngrok.log"; exit 1; }

# 4. Check every model is reachable through the public URL
TAGS=$(curl -sf -m 15 "$URL/api/tags") || { echo "tunnel is up but Ollama is not reachable through $URL"; exit 1; }
for m in "${MODELS[@]}"; do
  echo "$TAGS" | jq -e --arg m "$m" '.models[] | select(.name == $m)' >/dev/null \
    || { echo "$m not listed through the tunnel"; exit 1; }
done

[ -n "${SAVE_TO:-}" ] && echo "${SAVE_KEY:-OLLAMA_URL}=$URL" > "$SAVE_TO"

echo
echo "Serving: ${MODELS[*]}"
echo "URL:     $URL"
echo "Test:    curl -s $URL/api/generate -d '{\"model\":\"${MODELS[0]}\",\"prompt\":\"hi\",\"stream\":false}'"
echo "Anyone with this URL can use these models. Ctrl+C to stop."
wait "$NGROK_PID"
