#!/usr/bin/env bash
# package.sh — produce per-platform release ZIPs from a fully-built tree.
# Prerequisites: scripts/build-linux.sh AND scripts/build-windows.sh already ran.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

VERSION="${CLAUDE_DROPIN_VERSION:-0.1}"
DIST_DIR="$ROOT_DIR/dist"
LINUX_STAGE="$DIST_DIR/stage-linux/claude-dropin-v${VERSION}"
WIN_STAGE="$DIST_DIR/stage-win32/claude-dropin-v${VERSION}"

# ── Preflight ──────────────────────────────────────────────────────────
[[ -x "$ROOT_DIR/vendor/linux-x64/claude" ]] \
  || { echo "ERROR: vendor/linux-x64/claude missing. Run scripts/build-linux.sh." >&2; exit 1; }
[[ -f "$ROOT_DIR/vendor/win32-x64/claude.exe" ]] \
  || { echo "ERROR: vendor/win32-x64/claude.exe missing. Run scripts/build-windows.sh." >&2; exit 1; }
[[ -f "$ROOT_DIR/vendor/git-for-windows/cmd/git.exe" ]] \
  || { echo "ERROR: vendor/git-for-windows/cmd/git.exe missing. Run scripts/build-windows.sh." >&2; exit 1; }

# ── Clean + stage ──────────────────────────────────────────────────────
rm -rf "$DIST_DIR"
mkdir -p "$LINUX_STAGE" "$WIN_STAGE"

# Common files (both platforms)
for f in README.md LICENSE CREDITS.md; do
  cp "$ROOT_DIR/$f" "$LINUX_STAGE/$f"
  cp "$ROOT_DIR/$f" "$WIN_STAGE/$f"
done

# Empty dirs end-users need
for stage in "$LINUX_STAGE" "$WIN_STAGE"; do
  mkdir -p "$stage/config" "$stage/work"
  # config stays empty until setup; work needs a .gitkeep-equivalent so
  # the dir exists after extraction (zip doesn't store empty dirs well
  # across all extractors). An empty .keep is the convention.
  : > "$stage/work/.keep"
  : > "$stage/config/.keep"
done

# ── Linux tree ─────────────────────────────────────────────────────────
echo "==> Staging Linux tree..."
cp "$ROOT_DIR/run.sh" "$ROOT_DIR/setup.sh" "$ROOT_DIR/eject.sh" "$ROOT_DIR/update.sh" "$LINUX_STAGE/"
mkdir -p "$LINUX_STAGE/lib" "$LINUX_STAGE/templates/linux" "$LINUX_STAGE/vendor/linux-x64"
cp "$ROOT_DIR/lib/common.sh" "$LINUX_STAGE/lib/common.sh"
cp -R "$ROOT_DIR/templates/linux/." "$LINUX_STAGE/templates/linux/"
# Copy vendor/linux-x64 with -L to resolve any symlinks (cross-FS safety).
cp -L "$ROOT_DIR/vendor/linux-x64/"* "$LINUX_STAGE/vendor/linux-x64/"

# ── Windows tree ───────────────────────────────────────────────────────
echo "==> Staging Windows tree..."
cp "$ROOT_DIR/run.cmd" "$ROOT_DIR/setup.cmd" "$ROOT_DIR/eject.cmd" "$ROOT_DIR/update.cmd" "$WIN_STAGE/"
mkdir -p "$WIN_STAGE/templates/windows/skills" "$WIN_STAGE/vendor/win32-x64" \
         "$WIN_STAGE/vendor/git-for-windows"
cp -R "$ROOT_DIR/templates/windows/." "$WIN_STAGE/templates/windows/"
cp -L "$ROOT_DIR/vendor/win32-x64/"* "$WIN_STAGE/vendor/win32-x64/"
# MinGit tree: dereference symlinks (exFAT/FAT32 safety for USB use).
cp -RL "$ROOT_DIR/vendor/git-for-windows/." "$WIN_STAGE/vendor/git-for-windows/"

# ── Create ZIPs ────────────────────────────────────────────────────────
echo "==> Zipping linux-x64 release..."
( cd "$DIST_DIR/stage-linux" \
  && zip -qr -X "../claude-dropin-v${VERSION}-linux-x64.zip" "claude-dropin-v${VERSION}" )

echo "==> Zipping win32-x64 release..."
( cd "$DIST_DIR/stage-win32" \
  && zip -qr -X "../claude-dropin-v${VERSION}-win32-x64.zip" "claude-dropin-v${VERSION}" )

# ── Summary ────────────────────────────────────────────────────────────
echo
echo "Release artifacts:"
for z in "$DIST_DIR"/claude-dropin-v${VERSION}-*.zip; do
  sha="$(sha256sum "$z" | awk '{print $1}')"
  size="$(du -h "$z" | awk '{print $1}')"
  printf '  %s  %s  %s\n' "$size" "$sha" "$(basename "$z")"
done

# Cleanup staging
rm -rf "$DIST_DIR/stage-linux" "$DIST_DIR/stage-win32"
