#!/usr/bin/env bash
# Create the encrypted keystore wallets and save their addresses to scripts/wallets.env.
# deployer, verifier, machine1 (1B), machine2 (3B), user. Existing wallets are kept.
set -euo pipefail
DIR="$(dirname "$0")"
for n in deployer verifier machine1 machine2 user; do
  if cast wallet list | grep -qx "$n (Local)"; then echo "$n already exists"; else cast wallet new "$n" -p; fi
done
echo "Reading addresses (asks each password):"
{
  echo "DEPLOYER=$(cast wallet address --account deployer)"
  echo "VERIFIER=$(cast wallet address --account verifier)"
  echo "MACHINE1=$(cast wallet address --account machine1)"
  echo "MACHINE2=$(cast wallet address --account machine2)"
  echo "ME=$(cast wallet address --account user)"
  echo "USER_ACCOUNT=user"
} > "$DIR/wallets.env"
cat "$DIR/wallets.env"
