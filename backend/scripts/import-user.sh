#!/usr/bin/env bash
# One time: import the user's MetaMask private key into a cast wallet so the scripts can sign as that user.
# MetaMask: account menu → Account details → Show private key. Paste it when asked (it isn't echoed).
set -euo pipefail
source "$(dirname "$0")/config.sh"
need ME
cast wallet list | grep -qx "$USER_ACCOUNT (Local)" && { echo "$USER_ACCOUNT already exists"; exit 0; }
cast wallet import "$USER_ACCOUNT" --interactive
GOT=$(cast wallet address --account "$USER_ACCOUNT")
if [ "$(echo "$GOT" | tr A-F a-f)" != "$(echo "$ME" | tr A-F a-f)" ]; then
  rm -f "$HOME/.foundry/keystores/$USER_ACCOUNT"
  echo "That key is for $GOT, not $ME. Nothing saved."; exit 1
fi
echo "Imported $USER_ACCOUNT for $ME"
