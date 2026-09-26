# Shared settings, sourced by every step script. Env vars override the saved values.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RPC="${RPC:-https://testnet-rpc.monad.xyz}"
export API="${API:-http://localhost:8000}"

# Saved values: wallets.env (01-create-wallets.sh), machine1.env (machine1-serve.sh),
# machine2.env (Machine 2's URL + model, set by hand), machine3.env (verifier machine URLs, set by hand),
# deployed.env (03-deploy.sh)
for f in wallets machine1 machine2 machine3 deployed; do
  if [ -f "$ROOT/scripts/$f.env" ]; then
    while IFS='=' read -r k v; do [ -n "$k" ] && [ -z "${!k:-}" ] && export "$k=$v"; done < "$ROOT/scripts/$f.env"
  fi
done

# Wallets: deployer (owner + Inference Service), verifier (Verification Service), machine1 (1B), machine2 (3B), user (ME)
export DEPLOYER="${DEPLOYER:-}" MACHINE1="${MACHINE1:-}" ME="${ME:-}" VERIFIER="${VERIFIER:-}"
# cast keystore that holds the key for ME (the user); import-user.sh creates it from a MetaMask key
export USER_ACCOUNT="${USER_ACCOUNT:-user}"
export MACHINE_1B_URL="${MACHINE_1B_URL:-}" CONTRACT="${CONTRACT:-}"
export MACHINE_3B_URL="${MACHINE_3B_URL:-}" MODEL_3B="${MODEL_3B:-llama3.2:3b}" MACHINE2="${MACHINE2:-}"

need_user_key() {
  cast wallet list | grep -qx "$USER_ACCOUNT (Local)" || {
    echo "No cast wallet '$USER_ACCOUNT' holds the key for $ME. Run: ./import-user.sh"; exit 1; }
}
need() { for v in "$@"; do [ -n "${!v}" ] || { echo "$v is not set: run the earlier step scripts first"; exit 1; }; done; }
