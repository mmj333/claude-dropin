#!/usr/bin/env bash
# build-windows.sh — populate vendor/win32-x64/ + vendor/PortableGit/ from a
# Linux build host. No Wine or Windows required.
# Idempotent: skips downloads that already match the pinned SHA256.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/lib/common.sh"

# ── Pinned versions + SHA256s ──────────────────────────────────────────
CLAUDE_VERSION="2.1.119"
CLAUDE_WIN_URL="https://registry.npmjs.org/@anthropic-ai/claude-code-win32-x64/-/claude-code-win32-x64-${CLAUDE_VERSION}.tgz"
CLAUDE_WIN_SHA256="c2f883b48fce210d4059e68a7d7b88c44766229684b6f2dfdbfa2398c1f3cfa6"

AGE_VERSION="1.3.1"
AGE_WIN_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-windows-amd64.zip"
AGE_WIN_SHA256="c56e8ce22f7e80cb85ad946cc82d198767b056366201d3e1a2b93d865be38154"

GIT_VERSION="2.54.0"
# MinGit — minimal Git for Windows (~40 MB zip / ~97 MB unpacked). Swap to the
# full PortableGit-${GIT_VERSION}-64-bit.7z.exe if any git operation ever needs
# the bash / mingw Unix-tool environment.
GIT_WIN_URL="https://github.com/git-for-windows/git/releases/download/v${GIT_VERSION}.windows.1/MinGit-${GIT_VERSION}-64-bit.zip"
GIT_WIN_SHA256="04f937e1f0918b17b9be6f2294cb2bb66e96e1d9832d1c298e2de088a1d0e668"

# ── Preflight ──────────────────────────────────────────────────────────
for t in curl unzip sha256sum; do
  command -v "$t" >/dev/null || {
    echo "ERROR: missing required tool: $t" >&2
    exit 1
  }
done

# ── Paths ──────────────────────────────────────────────────────────────
VENDOR_DIR="$ROOT_DIR/vendor/win32-x64"
GIT_DIR="$ROOT_DIR/vendor/git-for-windows"
CACHE_DIR="$ROOT_DIR/.build-cache"
mkdir -p "$VENDOR_DIR" "$CACHE_DIR"

# ── Claude Code ────────────────────────────────────────────────────────
claude_tgz="$CACHE_DIR/claude-code-win32-x64-${CLAUDE_VERSION}.tgz"
if [[ ! -f "$claude_tgz" ]] || ! assert_file_sha256 "$claude_tgz" "$CLAUDE_WIN_SHA256" 2>/dev/null; then
  echo "==> Downloading Claude Code ${CLAUDE_VERSION} (win32-x64)..."
  download_and_verify "$CLAUDE_WIN_URL" "$claude_tgz" "$CLAUDE_WIN_SHA256"
else
  echo "==> Claude Code tarball cached + verified."
fi
echo "==> Extracting claude.exe..."
tmp_cc="$(mktemp -d)"
trap 'rm -rf "$tmp_cc"' EXIT
tar -xzf "$claude_tgz" -C "$tmp_cc"
install -m 0755 "$tmp_cc/package/claude.exe" "$VENDOR_DIR/claude.exe"
install -m 0644 "$tmp_cc/package/LICENSE.md" "$VENDOR_DIR/LICENSE.md"
rm -rf "$tmp_cc"

# ── age ────────────────────────────────────────────────────────────────
age_zip="$CACHE_DIR/age-v${AGE_VERSION}-windows-amd64.zip"
if [[ ! -f "$age_zip" ]] || ! assert_file_sha256 "$age_zip" "$AGE_WIN_SHA256" 2>/dev/null; then
  echo "==> Downloading age ${AGE_VERSION} (windows-amd64)..."
  download_and_verify "$AGE_WIN_URL" "$age_zip" "$AGE_WIN_SHA256"
else
  echo "==> age zip cached + verified."
fi
echo "==> Extracting age Windows binaries..."
tmp_age="$(mktemp -d)"
trap 'rm -rf "$tmp_age"' EXIT
unzip -q -o "$age_zip" -d "$tmp_age"
for bin in age age-keygen age-plugin-batchpass; do
  install -m 0755 "$tmp_age/age/${bin}.exe" "$VENDOR_DIR/${bin}.exe"
done
rm -rf "$tmp_age"

# ── MinGit (bundled Git for Windows, minimal flavor) ───────────────────
git_zip="$CACHE_DIR/MinGit-${GIT_VERSION}-64-bit.zip"
if [[ ! -f "$git_zip" ]] || ! assert_file_sha256 "$git_zip" "$GIT_WIN_SHA256" 2>/dev/null; then
  echo "==> Downloading MinGit ${GIT_VERSION} (~40 MB)..."
  download_and_verify "$GIT_WIN_URL" "$git_zip" "$GIT_WIN_SHA256"
else
  echo "==> MinGit cached + verified."
fi
if [[ -d "$GIT_DIR" ]] && [[ -x "$GIT_DIR/cmd/git.exe" ]]; then
  echo "==> MinGit already extracted at $GIT_DIR, skipping."
else
  echo "==> Extracting MinGit (~370 files, ~97 MB uncompressed)..."
  rm -rf "$GIT_DIR"
  mkdir -p "$GIT_DIR"
  unzip -q -o "$git_zip" -d "$GIT_DIR"
fi

# ── Smoke test (structural — we can't run PE binaries from Linux) ──────
echo "==> Structural verification..."
for f in "$VENDOR_DIR/claude.exe" "$VENDOR_DIR/age.exe" \
         "$VENDOR_DIR/age-keygen.exe" "$VENDOR_DIR/age-plugin-batchpass.exe" \
         "$GIT_DIR/cmd/git.exe"; do
  [[ -f "$f" ]] || { echo "MISSING: $f" >&2; exit 1; }
  file "$f" | grep -q "PE32+ executable" \
    || { echo "NOT A PE BINARY: $f" >&2; exit 1; }
done
echo "==> vendor/win32-x64/ ready:"
ls -lh "$VENDOR_DIR/" | head -20
echo "==> vendor/git-for-windows/ ready ($(find "$GIT_DIR" -type f | wc -l) files, $(du -sh "$GIT_DIR" | awk '{print $1}') total)"
