#!/usr/bin/env bash
# eject.sh — idempotent force-encrypt + shred.
# Use when a crash (or kill -9) left a decrypted scratch dir behind.
# No-op if no scratch is found.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

AGE_BIN="$SCRIPT_DIR/vendor/linux-x64/age"
CONFIG_DIR="$SCRIPT_DIR/config"

cleanup_stale_new "$CONFIG_DIR"

# Search all plausible scratch locations.
candidates=()
for d in /dev/shm/claude-dropin.*; do
  [[ -d "$d" ]] && candidates+=("$d")
done
[[ -d "$CONFIG_DIR/scratch" ]] && candidates+=("$CONFIG_DIR/scratch")

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "Nothing to eject — no scratch dir found." >&2
  exit 0
fi

for scratch in "${candidates[@]}"; do
  echo "==> Encrypting $scratch → $CONFIG_DIR/claude.age" >&2
  encrypt_blob "$AGE_BIN" "$CONFIG_DIR" "$scratch"
  shred_dir "$scratch"
  echo "==> Ejected $scratch" >&2
done
