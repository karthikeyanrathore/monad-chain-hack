# Shared settings, sourced by every step script. Env vars override the saved values.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RPC="${RPC:-https://testnet-rpc.monad.xyz}"
export API="${API:-http://localhost:8000}"

# Saved values: wallets.env (01-create-wallets.sh), machine1.env (machine1-serve.sh), deployed.env (03-deploy.sh)
for f in wallets machine1 deployed; do
  if [ -f "$ROOT/scripts/$f.env" ]; then
    while IFS='=' read -r k v; do [ -n "$k" ] && [ -z "${!k:-}" ] && export "$k=$v"; done < "$ROOT/scripts/$f.env"
  fi
done

# Wallets: deployer (owner + Inference Service + verifier for now), machine1 (1B provider), user (ME)
export DEPLOYER="${DEPLOYER:-}" MACHINE1="${MACHINE1:-}" ME="${ME:-}"
export MACHINE_1B_URL="${MACHINE_1B_URL:-}" CONTRACT="${CONTRACT:-}"

need() { for v in "$@"; do [ -n "${!v}" ] || { echo "$v is not set: run the earlier step scripts first"; exit 1; }; done; }
