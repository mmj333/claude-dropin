#!/usr/bin/env bash
# update.sh — pull latest scripts/templates from github.com/mmj333/claude-dropin.
#
# PRESERVES (nothing in these dirs is touched):
#   config/    your encrypted blob + identity + recipient + any scratch
#   work/      your session transcripts
#   vendor/    bundled binaries (claude, age, MinGit, etc.)
#   dist/      release artifacts you may have built locally
#   .build-cache/
#
# UPDATES (replaces from main):
#   run.sh, setup.sh, eject.sh, update.sh
#   lib/*
#   scripts/*
#   templates/*
#   README.md, CREDITS.md, LICENSE, .gitignore
#
# DOES NOT update bundled binaries (vendor/). For that, re-run
# scripts/build-linux.sh after update, or re-download the release ZIP.
#
# Usage:
#   ./update.sh                      # update from main
#   ./update.sh some-branch-name     # update from an alternate branch
#
# First-time install (no existing update.sh):
#   curl -fsSL https://raw.githubusercontent.com/mmj333/claude-dropin/main/update.sh -o update.sh
#   chmod +x update.sh
#   ./update.sh

set -euo pipefail

SCRIPT_DIR="$( cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd )"
REPO="mmj333/claude-dropin"
BRANCH="${1:-main}"
TARBALL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> Fetching ${REPO}@${BRANCH}..."
if ! curl -fsSL "$TARBALL" -o "$tmp/src.tar.gz"; then
  echo "ERROR: download failed. Check network + whether the branch exists." >&2
  exit 1
fi

mkdir -p "$tmp/extract"
tar -xzf "$tmp/src.tar.gz" -C "$tmp/extract" --strip-components=1

echo "==> Overlaying updates onto $SCRIPT_DIR..."

# Use rsync if available (clean exclude semantics); fall back to a manual
# cp loop if the host is missing rsync (rare on Linux, present on most boxes).
if command -v rsync >/dev/null; then
  rsync -a --itemize-changes \
    --exclude='/config/' \
    --exclude='/work/' \
    --exclude='/vendor/' \
    --exclude='/dist/' \
    --exclude='/.build-cache/' \
    --exclude='/.git/' \
    "$tmp/extract/" "$SCRIPT_DIR/" | sed 's/^/    /'
else
  # Minimal fallback: copy the top-level known-safe files + top-level dirs
  # except the protected ones.
  ( cd "$tmp/extract" && find . -mindepth 1 -maxdepth 1 \
      ! -name config ! -name work ! -name vendor ! -name dist \
      ! -name .build-cache ! -name .git ) \
    | while read -r entry; do
        cp -rT "$tmp/extract/${entry#./}" "$SCRIPT_DIR/${entry#./}"
      done
fi

# Make sure shell scripts stay executable (tarball does preserve the bit,
# but belt-and-suspenders).
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/scripts"/*.sh 2>/dev/null || true

echo
echo "==> Update complete."
if [[ -f "$SCRIPT_DIR/README.md" ]]; then
  # Show the top of README so user sees what version they're on.
  head -3 "$SCRIPT_DIR/README.md" | sed 's/^/    /'
fi
echo
echo "Bundled binaries in vendor/ were not touched."
echo "If you need fresher claude / age / MinGit, re-run:"
echo "  ./scripts/build-linux.sh    (Linux)"
echo "  ./scripts/build-windows.sh  (cross-build from Linux for Windows ZIP)"
