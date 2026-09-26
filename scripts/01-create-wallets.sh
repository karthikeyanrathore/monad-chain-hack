#!/usr/bin/env bash
# Create the three encrypted keystore wallets and save their addresses to scripts/wallets.env.
set -euo pipefail
DIR="$(dirname "$0")"
for n in deployer machine1 user; do
  if cast wallet list | grep -qx "$n (Local)"; then echo "$n already exists"; else cast wallet new "$n" -p; fi
done
echo "Reading addresses (asks each password):"
{
  echo "DEPLOYER=$(cast wallet address --account deployer)"
  echo "MACHINE1=$(cast wallet address --account machine1)"
  echo "ME=$(cast wallet address --account user)"
} > "$DIR/wallets.env"
cat "$DIR/wallets.env"
