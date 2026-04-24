#!/usr/bin/env bash
# build-linux.sh — populate vendor/linux-x64/ with Claude Code + age binaries.
# Idempotent: skips downloads that already match the pinned SHA256.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/lib/common.sh"

# ── Pinned versions + SHA256s ──────────────────────────────────────────
CLAUDE_VERSION="2.1.119"
CLAUDE_LINUX_URL="https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/-/claude-code-linux-x64-${CLAUDE_VERSION}.tgz"
CLAUDE_LINUX_SHA256="2a97954a862fc1dc096601f011eb46adeea0d95d08ac98fcd272ca1681ae9ca8"

AGE_VERSION="1.3.1"
AGE_LINUX_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz"
AGE_LINUX_SHA256="bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377"

# ── Paths ──────────────────────────────────────────────────────────────
VENDOR_DIR="$ROOT_DIR/vendor/linux-x64"
CACHE_DIR="$ROOT_DIR/.build-cache"
mkdir -p "$VENDOR_DIR" "$CACHE_DIR"

# ── Claude Code ────────────────────────────────────────────────────────
claude_tgz="$CACHE_DIR/claude-code-linux-x64-${CLAUDE_VERSION}.tgz"
if [[ ! -f "$claude_tgz" ]] || ! assert_file_sha256 "$claude_tgz" "$CLAUDE_LINUX_SHA256" 2>/dev/null; then
  echo "==> Downloading Claude Code ${CLAUDE_VERSION} (linux-x64)..."
  download_and_verify "$CLAUDE_LINUX_URL" "$claude_tgz" "$CLAUDE_LINUX_SHA256"
else
  echo "==> Claude Code tarball cached + verified."
fi
echo "==> Extracting Claude Code binary..."
tar -xzf "$claude_tgz" -C "$CACHE_DIR" --transform='s|^package/||' package/claude package/LICENSE.md
install -m 0755 "$CACHE_DIR/claude" "$VENDOR_DIR/claude"
install -m 0644 "$CACHE_DIR/LICENSE.md" "$VENDOR_DIR/LICENSE.md"
rm -f "$CACHE_DIR/claude" "$CACHE_DIR/LICENSE.md"

# ── age + tools ────────────────────────────────────────────────────────
age_tgz="$CACHE_DIR/age-v${AGE_VERSION}-linux-amd64.tar.gz"
if [[ ! -f "$age_tgz" ]] || ! assert_file_sha256 "$age_tgz" "$AGE_LINUX_SHA256" 2>/dev/null; then
  echo "==> Downloading age ${AGE_VERSION} (linux-amd64)..."
  download_and_verify "$AGE_LINUX_URL" "$age_tgz" "$AGE_LINUX_SHA256"
else
  echo "==> age tarball cached + verified."
fi
echo "==> Extracting age binaries..."
tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT
tar -xzf "$age_tgz" -C "$tmpd"
for bin in age age-keygen age-plugin-batchpass; do
  install -m 0755 "$tmpd/age/$bin" "$VENDOR_DIR/$bin"
done

# ── Smoke test ─────────────────────────────────────────────────────────
echo "==> Smoke testing binaries..."
"$VENDOR_DIR/claude" --version
"$VENDOR_DIR/age" --version
echo "==> vendor/linux-x64/ ready:"
ls -lh "$VENDOR_DIR/"
