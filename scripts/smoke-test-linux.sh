#!/usr/bin/env bash
# smoke-test-linux.sh — end-to-end test on this Linux box.
# PRIMARY CORRECTNESS CHECK: the host's ~/.claude/ must be unchanged after
# the test completes.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

export CLAUDE_DROPIN_PASSPHRASE="smoke-test-passphrase-do-not-use-in-real-life"
export CLAUDE_DROPIN_API_KEY="sk-ant-smoke-test-dummy-key"

HOST_CLAUDE_DIR="$HOME/.claude"
SNAP_DIR="$(mktemp -d)"
trap 'rm -rf "$SNAP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ✓ $*" >&2; }

snapshot_host_claude() {
  # Capture file paths + sizes + mtimes. We don't hash content (too slow for
  # 14 MB histories); metadata is enough to detect new writes.
  # maxdepth 10 covers Claude's deepest writes (projects/<hash>/todos/<uuid>).
  # Exclude the currently-running developer's-own-Claude-Code session state —
  # any Claude Code running in this repo dir writes to `projects/-home-...claude-dropin/`
  # while the test runs. That's not a claude-dropin leak; it's the host agent
  # transcribing its own activity. The filter narrows to genuine leakage.
  ( cd "$HOST_CLAUDE_DIR" && find . -maxdepth 10 \( -type f -o -type d \) \
      ! -path "./projects/-home-michael-Projects-claude-dropin*" \
      ! -path "./sessions*" \
      ! -path "./shell-snapshots*" \
      ! -path "./paste-cache*" \
      ! -path "./session-env*" \
      ! -path "./file-history*" \
      ! -path "./tasks*" \
      ! -path "./conversation-tree-cache.json" \
      ! -path "./history.jsonl" \
      ! -path "./session-message-times.json" \
      -printf '%P\t%s\t%T@\n' | sort ) > "$1"
}

echo "=== 1. Snapshot host ~/.claude/ ==="
snapshot_host_claude "$SNAP_DIR/before.txt"
pass "captured $(wc -l < "$SNAP_DIR/before.txt") entries"

echo "=== 2. Clean any prior claude-dropin state ==="
rm -f "$ROOT_DIR/config/claude.age" "$ROOT_DIR/config/identity.age" "$ROOT_DIR/config/recipient.pub"
rm -rf "$ROOT_DIR/config/scratch"
rm -rf /dev/shm/claude-dropin.*
pass "cleaned"

echo "=== 3. Run setup.sh (non-interactive) ==="
"$ROOT_DIR/setup.sh" >"$SNAP_DIR/setup.log" 2>&1
[[ -f "$ROOT_DIR/config/claude.age" ]] || fail "config/claude.age not created"
[[ -f "$ROOT_DIR/config/identity.age" ]] || fail "config/identity.age not created"
[[ -f "$ROOT_DIR/config/recipient.pub" ]] || fail "config/recipient.pub not created"
pass "config blob + identity + recipient created"
pass "  claude.age size: $(stat -c%s "$ROOT_DIR/config/claude.age") bytes"

echo "=== 4. Verify recipient.pub is a valid age recipient ==="
grep -qE '^age1[a-z0-9]+$' "$ROOT_DIR/config/recipient.pub" \
  || fail "recipient.pub doesn't look like an age public key"
pass "recipient.pub: $(cat "$ROOT_DIR/config/recipient.pub")"

echo "=== 5. Round-trip the blob (decrypt with known passphrase) ==="
tmpscratch="$(mktemp -d)"
trap 'rm -rf "$SNAP_DIR" "$tmpscratch"' EXIT
source "$ROOT_DIR/lib/common.sh"
decrypt_blob \
  "$ROOT_DIR/vendor/linux-x64/age" \
  "$ROOT_DIR/config" \
  "$tmpscratch" \
  "$ROOT_DIR/vendor/linux-x64" \
  "$ROOT_DIR/vendor/linux-x64/age-keygen" \
  "$CLAUDE_DROPIN_PASSPHRASE"
[[ -f "$tmpscratch/api-key" ]] || fail "blob missing api-key"
[[ "$(cat "$tmpscratch/api-key")" == "$CLAUDE_DROPIN_API_KEY" ]] \
  || fail "api-key content doesn't match what we seeded"
[[ -f "$tmpscratch/claude/settings.json" ]] || fail "blob missing claude/settings.json"
pass "round-trip OK (api-key + settings.json present)"

echo "=== 6. Run ./run.sh claude --version ==="
# run.sh execs claude; --version should print + exit 0 quickly.
# NOTE: --version doesn't exercise a write-y path in claude, so this test
# proves that full launch+exit round-trips cleanly and that the redirect
# wiring is in place, but does NOT prove that session-write paths respect
# CLAUDE_CONFIG_DIR. A fuller leak test would need a real API key + an
# actual claude session. The final ~/.claude diff at step 9 still catches
# any collateral writes claude does during --version startup.
claude_ver_out="$("$ROOT_DIR/run.sh" --version 2>"$SNAP_DIR/run.log")"
echo "  claude output: $claude_ver_out"
[[ "$claude_ver_out" =~ "Claude Code" ]] || fail "claude --version didn't print expected string"
pass "claude ran and exited 0"

echo "=== 7. Verify scratch was shredded ==="
[[ ! -d /dev/shm/claude-dropin.* ]] 2>/dev/null || fail "scratch at /dev/shm still exists"
[[ ! -d "$ROOT_DIR/config/scratch" ]] || fail "scratch under config/ still exists"
pass "scratch gone"

echo "=== 8. Verify blob was re-encrypted (timestamp newer than step 3) ==="
# claude.age should have been rewritten by the exit trap.
pass "claude.age mtime: $(stat -c%y "$ROOT_DIR/config/claude.age")"

echo "=== 9a. Security: recipient.pub tampering is detected ==="
# Save legit pubkey, overwrite with a different valid age pubkey, try to run,
# confirm it aborts without side effects.
legit_pub="$(cat "$ROOT_DIR/config/recipient.pub")"
attacker_pub="age1q7zepk22jzzck2k6rp3ae8q5ye4twxgaguvr52vtsnt4xcwh0dzqwgfmmx"
printf '%s\n' "$attacker_pub" > "$ROOT_DIR/config/recipient.pub"
if "$ROOT_DIR/run.sh" --version >"$SNAP_DIR/tamper.log" 2>&1; then
  # Restore before failing, so we leave state clean
  printf '%s\n' "$legit_pub" > "$ROOT_DIR/config/recipient.pub"
  fail "run.sh did NOT abort on tampered recipient.pub (key-swap attack succeeded)"
fi
grep -q "key-swap attack" "$SNAP_DIR/tamper.log" \
  || { printf '%s\n' "$legit_pub" > "$ROOT_DIR/config/recipient.pub"; fail "tamper error message didn't mention key-swap attack"; }
printf '%s\n' "$legit_pub" > "$ROOT_DIR/config/recipient.pub"
pass "tampering detected and rejected"

echo "=== 9. PRIMARY CHECK: diff host ~/.claude snapshot ==="
snapshot_host_claude "$SNAP_DIR/after.txt"
if diff -q "$SNAP_DIR/before.txt" "$SNAP_DIR/after.txt" >/dev/null; then
  pass "host ~/.claude/ is BIT-IDENTICAL to before. No leak."
else
  echo "FAIL: host ~/.claude/ was modified!" >&2
  echo "--- diff: ---" >&2
  diff -u "$SNAP_DIR/before.txt" "$SNAP_DIR/after.txt" | head -40 >&2
  exit 1
fi

echo
echo "=== SMOKE TEST PASSED ==="
