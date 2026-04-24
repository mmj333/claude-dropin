#!/usr/bin/env bash
# setup.sh — first-time (or --force re-key) setup.
# Prompts passphrase + API key, generates X25519 identity wrapped with the
# passphrase, seeds initial config tree from templates/linux/, encrypts
# everything into config/claude.age.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

AGE_BIN="$SCRIPT_DIR/vendor/linux-x64/age"
AGE_KEYGEN="$SCRIPT_DIR/vendor/linux-x64/age-keygen"
PLUGIN_DIR="$SCRIPT_DIR/vendor/linux-x64"
CONFIG_DIR="$SCRIPT_DIR/config"
TEMPLATE_DIR="$SCRIPT_DIR/templates/linux"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; fi

# ── Preflight ─────────────────────────────────────────────────────────
if [[ ! -x "$AGE_BIN" || ! -x "$AGE_KEYGEN" ]]; then
  echo "ERROR: age binaries not found at $PLUGIN_DIR." >&2
  echo "Run: ./scripts/build-linux.sh first." >&2
  exit 1
fi

if [[ -f "$CONFIG_DIR/claude.age" && "$FORCE" != 1 ]]; then
  echo "ERROR: $CONFIG_DIR/claude.age already exists." >&2
  echo "Use --force to overwrite (destroys existing session state)." >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR"
cleanup_stale_new "$CONFIG_DIR"

# ── 1. Passphrase ─────────────────────────────────────────────────────
if [[ -n "${CLAUDE_DROPIN_PASSPHRASE:-}" ]]; then
  # Non-interactive path (scripting / smoke tests). Plugin path.
  pw="$CLAUDE_DROPIN_PASSPHRASE"
else
  # Interactive path. age -p handles the prompt directly; no plugin used.
  cat <<'EOF' >&2
Setting up claude-dropin.

You'll choose a passphrase now. This passphrase decrypts your stored API key
and session history every time you launch. There is no recovery path — if you
forget it, the encrypted state is permanently unreadable.
EOF
  pw=""  # empty → wrap_identity takes the interactive path.
fi

# ── 2. API key (optional) ─────────────────────────────────────────────
if [[ -n "${CLAUDE_DROPIN_API_KEY+x}" ]]; then
  api_key="$CLAUDE_DROPIN_API_KEY"
else
  cat <<'EOF' >&2

Enter your Anthropic API key (starts with sk-ant-…), or leave blank to
configure OAuth from inside Claude Code on first launch.
EOF
  api_key="$(prompt_password 'API key (blank for OAuth): ')"
fi

# ── 3. Generate + wrap identity ───────────────────────────────────────
tmpd="$(mktemp -d)"
trap 'shred_dir "$tmpd"' EXIT
chmod 700 "$tmpd"

echo "==> Generating X25519 identity..." >&2
"$AGE_KEYGEN" -o "$tmpd/identity.plain" 2>/dev/null
chmod 600 "$tmpd/identity.plain"
recipient="$("$AGE_KEYGEN" -y "$tmpd/identity.plain")"
if [[ -z "$recipient" ]]; then
  echo "ERROR: age-keygen did not report a public key." >&2
  exit 1
fi

echo "==> Wrapping identity with passphrase..." >&2
wrap_identity "$AGE_BIN" "$PLUGIN_DIR" \
  "$tmpd/identity.plain" "$CONFIG_DIR/identity.age" "$pw"

printf '%s\n' "$recipient" > "$CONFIG_DIR/recipient.pub"

# ── 4. Seed initial scratch tree ──────────────────────────────────────
seed="$tmpd/seed"
mkdir -p "$seed/claude/skills"
chmod 700 "$seed"

if [[ -n "$api_key" ]]; then
  umask 077
  printf '%s\n' "$api_key" > "$seed/api-key"
  umask 022
fi

# Copy settings.json (if template exists)
if [[ -f "$TEMPLATE_DIR/settings.json" ]]; then
  cp "$TEMPLATE_DIR/settings.json" "$seed/claude/settings.json"
fi
if [[ -f "$TEMPLATE_DIR/CLAUDE.md" ]]; then
  cp "$TEMPLATE_DIR/CLAUDE.md" "$seed/claude/CLAUDE.md"
fi
if [[ -d "$TEMPLATE_DIR/skills" ]]; then
  cp -R "$TEMPLATE_DIR/skills/." "$seed/claude/skills/"
fi

# ── 5. Encrypt seed into claude.age ───────────────────────────────────
echo "==> Encrypting initial session state..." >&2
encrypt_blob "$AGE_BIN" "$CONFIG_DIR" "$seed"

# ── 6. Summary ────────────────────────────────────────────────────────
cat <<EOF >&2

Setup complete.

  config/identity.age   — X25519 identity wrapped with your passphrase
  config/recipient.pub  — public key (cleartext; safe)
  config/claude.age     — encrypted initial session state

Launch with: ./run.sh
Rekey with:  ./setup.sh --force   (destroys existing state)
EOF
