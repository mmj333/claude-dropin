#!/usr/bin/env bash
# run.sh — launch Claude Code with encrypted, folder-local config.
# Decrypts config/claude.age to a scratch dir (/dev/shm if available),
# sets CLAUDE_CONFIG_DIR, cd's into work/, execs claude, and re-encrypts
# the scratch back to config/claude.age on exit.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CLAUDE_BIN="$SCRIPT_DIR/vendor/linux-x64/claude"
AGE_BIN="$SCRIPT_DIR/vendor/linux-x64/age"
AGE_KEYGEN="$SCRIPT_DIR/vendor/linux-x64/age-keygen"
PLUGIN_DIR="$SCRIPT_DIR/vendor/linux-x64"
CONFIG_DIR="$SCRIPT_DIR/config"
WORK_DIR="$SCRIPT_DIR/work"

# ── Preflight ─────────────────────────────────────────────────────────
if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "ERROR: claude binary not found. Run ./scripts/build-linux.sh first." >&2
  exit 1
fi
if [[ ! -x "$AGE_BIN" ]]; then
  echo "ERROR: age binary not found. Run ./scripts/build-linux.sh first." >&2
  exit 1
fi
if [[ ! -f "$CONFIG_DIR/claude.age" ]]; then
  echo "No config blob found. Running setup..." >&2
  exec "$SCRIPT_DIR/setup.sh"
fi

# ── Clean any stale .age.new from a prior crashed encrypt ─────────────
cleanup_stale_new "$CONFIG_DIR"

# ── Pick scratch dir + cleanup trap ───────────────────────────────────
SCRATCH="$(locate_scratch_dir "$CONFIG_DIR")"
DECRYPTED=0

cleanup() {
  local ec=$?
  if [[ -d "$SCRATCH" ]]; then
    if [[ "$DECRYPTED" == "1" ]]; then
      echo "==> Re-encrypting session state..." >&2
      if encrypt_blob "$AGE_BIN" "$CONFIG_DIR" "$SCRATCH"; then
        shred_dir "$SCRATCH"
        echo "==> Ejected cleanly." >&2
      else
        echo "ERROR: re-encrypt failed. Scratch left at: $SCRATCH" >&2
        echo "  Run ./eject.sh to retry, or recover manually." >&2
      fi
    else
      # Decrypt failed — scratch is empty or partial. Do NOT re-encrypt
      # (would overwrite the legit blob with empty/attacker-keyed state).
      shred_dir "$SCRATCH"
    fi
  fi
  exit "$ec"
}
trap cleanup EXIT INT TERM

# ── Decrypt ───────────────────────────────────────────────────────────
echo "==> Unlocking config..." >&2
decrypt_blob "$AGE_BIN" "$CONFIG_DIR" "$SCRATCH" \
  "$PLUGIN_DIR" "$AGE_KEYGEN" "${CLAUDE_DROPIN_PASSPHRASE:-}"
DECRYPTED=1

# ── Env setup ─────────────────────────────────────────────────────────
export CLAUDE_CONFIG_DIR="$SCRATCH/claude"

# API key from blob (if present)
if [[ -f "$SCRATCH/api-key" ]]; then
  export ANTHROPIC_API_KEY="$(cat "$SCRATCH/api-key")"
fi

# Belt-and-suspenders: keep any subprocess writes inside SCRATCH.
export TMPDIR="$SCRATCH/tmp"
export XDG_CONFIG_HOME="$SCRATCH/xdg-config"
export XDG_CACHE_HOME="$SCRATCH/xdg-cache"
export XDG_DATA_HOME="$SCRATCH/xdg-data"
export XDG_STATE_HOME="$SCRATCH/xdg-state"
mkdir -p "$TMPDIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

# ── Pick per-host work subdir (session history scoped to the machine) ──
# Different hosts → different cwds → claude indexes their session
# histories separately. Matters most on USB flow where the same folder
# plugs into multiple machines. Set CLAUDE_DROPIN_SHARED_WORK=1 to opt
# back into a single shared work/ across hosts.
if [[ -z "${CLAUDE_DROPIN_SHARED_WORK:-}" ]]; then
  host_slug="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown-host)"
  # Sanitize for path safety: keep alnum, dash, underscore, dot.
  host_slug="$(printf '%s' "$host_slug" | tr -c 'A-Za-z0-9._-' '_')"
  WORK_DIR="$WORK_DIR/$host_slug"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Don't leak the passphrase (if we used the env-var path) into claude or
# anything it spawns.
unset CLAUDE_DROPIN_PASSPHRASE CLAUDE_DROPIN_API_KEY

echo "==> Launching Claude Code..." >&2
"$CLAUDE_BIN" "$@"
