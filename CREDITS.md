# Credits

## Design inspiration

[**portable-agent-usb**](https://github.com/AthusLopes/portable-agent-usb) by
Athus Lopes (MIT) was studied as a reference while designing this project.
No code was copied, but the following techniques were adopted:

- Path-relative launcher resolution on Windows via `%~dp0` and on Linux via
  `readlink -f "${BASH_SOURCE[0]}"`.
- Belt-and-suspenders env-var redirects alongside `CLAUDE_CONFIG_DIR`:
  `APPDATA`, `LOCALAPPDATA`, `TEMP`, `TMP`, `XDG_CONFIG_HOME` — defensive
  depth against any subprocess that bypasses `CLAUDE_CONFIG_DIR`.
- `cp -rL` to resolve symlinks when staging content destined for an exFAT
  (or FAT32) target, which has no symlink support.

portable-agent-usb differs in scope — it targets USB drives without
encryption and relies on plaintext API-key files — so the rest of this
project's architecture (age-encrypted config blob, passphrase-wrapped
X25519 identity, auto-encrypt on exit, field-diagnostic templates) was
built from scratch.

## Bundled binaries

- [`@anthropic-ai/claude-code`](https://www.npmjs.com/package/@anthropic-ai/claude-code)
  — Anthropic's Claude Code CLI. Platform-specific native binaries are
  fetched from npm and redistributed under the terms of Anthropic's license
  (see `vendor/<platform>/LICENSE.md` after build).
- [`age`](https://github.com/FiloSottile/age) — Filippo Valsorda, BSD-3-Clause.
  Fetched from GitHub Releases.
- [`MinGit`](https://git-scm.com/download/win) (Windows builds only) —
  minimal Git for Windows (same release line as PortableGit, trimmed for
  embedding), GPLv2. Fetched from git-for-windows GitHub releases.
