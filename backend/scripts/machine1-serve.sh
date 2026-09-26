#!/usr/bin/env bash
# Machine 1: serve llama3.2:1b through a public ngrok URL. Keep this running.
# The URL is saved to scripts/machine1.env, which 05-start-service.sh reads.
cd "$(dirname "$0")"
SAVE_TO=machine1.env SAVE_KEY=MACHINE_1B_URL exec ./serve-models.sh 1B
