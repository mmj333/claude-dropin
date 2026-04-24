# claude-dropin

Self-contained, drop-in runner for Claude Code. Extract the ZIP, double-click
a launcher, get a working Claude Code session in seconds — with all config,
credentials, and history encrypted to a passphrase and kept inside the folder.
Nothing lands on the host.

## Field quick-ref

| Host OS | Launcher | First-time setup |
|---|---|---|
| Windows 10/11 / Server 2016+ | double-click `run.cmd` | runs `setup.cmd` automatically if no config blob |
| Linux (x86_64) | `./run.sh` | runs `setup.sh` automatically if no config blob |

First launch prompts for a passphrase + an Anthropic API key. Subsequent
launches only prompt for the passphrase.

To cleanly encrypt and shut down from outside Claude Code: run `eject.cmd` or
`./eject.sh`. The normal exit path handles this automatically; `eject` is for
when a crash left a decrypted scratch dir behind.

## Anatomy

```
claude-dropin/
  run.{cmd,sh}          launcher — decrypts, runs claude, re-encrypts on exit
  setup.{cmd,sh}        first-time / re-key flow
  eject.{cmd,sh}        force-encrypt + shred any leftover scratch
  vendor/
    linux-x64/          Claude Code binary + age tools (linux x64)
    win32-x64/          Claude Code binary + age tools (windows x64)
    git-for-windows/    bundled MinGit (win32 only)
  config/
    claude.age          encrypted tarball of the full Claude Code config tree
    identity.age        X25519 identity wrapped with your passphrase
    recipient.pub       corresponding public key (cleartext)
  work/                 scratch cwd where Claude Code's project-local .claude/ lands
  templates/            baked-in CLAUDE.md, settings.json, and skill stubs
  scripts/              build + package scripts (used at release time, not at runtime)
  lib/                  shared bash helpers
```

## Building release artifacts

From a Linux x86_64 build host with `curl`, `tar`, `unzip`, `sha256sum`,
`p7zip-full` (for Windows PortableGit extraction):

```bash
./scripts/build-linux.sh       # populates vendor/linux-x64/
./scripts/build-windows.sh     # populates vendor/win32-x64/ + vendor/PortableGit/
./scripts/package.sh           # writes dist/claude-dropin-*.zip
```

Pinned versions + SHA256 hashes live at the top of each build script.

## Test path

1. **Linux smoke test** (gating):
   - `./scripts/build-linux.sh`
   - `./setup.sh` — supply a dummy passphrase and a real (or dummy) API key.
   - `./run.sh` — confirm Claude Code launches and `CLAUDE_CONFIG_DIR` is
     honored. Exit.
   - Verify the host's `~/.claude/` has zero new entries. This is the primary
     correctness criterion.
   - Verify `config/claude.age` was updated and `config/scratch/` was shredded.
2. **Windows smoke test** — cross-build from Linux, extract in a VM, run.
3. **Real box** — the field target.

## Non-interactive / CI use

Both `setup.*` and `run.*` honor two environment variables for scripted runs:

- `CLAUDE_DROPIN_PASSPHRASE` — supplies the passphrase, skipping the
  interactive prompt. When set, `setup.sh`/`run.sh` go through
  `age-plugin-batchpass` (vendored in `vendor/<platform>/`). Leave unset
  for normal interactive use — the plugin is then untouched and `age` runs
  native `-p` mode.
- `CLAUDE_DROPIN_API_KEY` — supplies the API key at setup time, skipping
  the prompt. Use `CLAUDE_DROPIN_API_KEY=""` to explicitly opt into the
  OAuth-from-Claude-Code flow.

Example (smoke test / CI):

```bash
CLAUDE_DROPIN_PASSPHRASE="$(cat my-passphrase)" \
CLAUDE_DROPIN_API_KEY="$ANTHROPIC_API_KEY" \
./setup.sh
CLAUDE_DROPIN_PASSPHRASE="$(cat my-passphrase)" \
./run.sh --version
```

The plugin binary (~4 MB) ships in every release ZIP so these overrides
work post-deployment, not just during build.

A third env var affects session indexing:

- `CLAUDE_DROPIN_SHARED_WORK=1` — disables the default "per-hostname"
  scratch cwd. By default `run.*` cd's into `work/<hostname>/` so that
  the same folder on a USB stick plugged into different customer boxes
  keeps session histories separate. Set this to `1` when you want a
  single shared project index across every machine you plug into.

## Encryption scheme

- `setup.*` generates an X25519 keypair via `age-keygen`.
- The private key (identity) is wrapped with your passphrase using
  `age -j batchpass` and written to `config/identity.age`. The public key
  is written cleartext to `config/recipient.pub`.
- Session state (API key + full Claude Code config tree) is tar'd and
  encrypted to the public key → `config/claude.age`. This encrypt step
  needs no passphrase (public-key encryption) so the EXIT-trap / eject
  path runs silently.
- `run.*` decrypts the identity (one passphrase prompt) then decrypts the
  blob to a scratch dir (`/dev/shm/claude-dropin.$$` on Linux,
  `config/scratch/` on Windows).
- On clean exit, the scratch dir is re-encrypted to the public key and
  shredded. On crash, `eject.*` can recover any leftover scratch.

## Windows v0.1 status — truth in labeling

The Windows `.cmd` launchers (`run.cmd`, `setup.cmd`, `eject.cmd`) were
written and structurally reviewed on the Linux build host. They have **not
been executed** — Linux cannot run `.cmd` files, and the bundled Windows
binaries (`claude.exe`, `age.exe`) won't run under Wine cleanly enough to
serve as a real smoke test. The `linux-x64.zip` release has passed a full
end-to-end leak test (`scripts/smoke-test-linux.sh`); the `win32-x64.zip`
release has passed structural checks only.

**Before carrying the Windows ZIP to a customer site:** extract it in a
Windows 10+ VM (or on a throwaway Windows box), run `setup.cmd` and
`run.cmd` end-to-end, and confirm a local `~/.claude/` equivalent
(`%USERPROFILE%\.claude\`) was not created. That exercise is the gating
criterion for treating `v0.1-win32-x64` as field-ready.

## Known issues

- **Windows SmartScreen** — first run of `run.cmd` from Downloads will prompt
  "Windows protected your PC → More info → Run anyway." Code signing is a
  later polish item.
- **Crash loses active session** — if the process dies hard (power cut, OOM),
  any session writes since the last clean exit are lost. Periodic
  auto-encrypt is a v1.1 item.
- **Git fallback** — we bundle MinGit (~40 MB zip) rather than the full
  PortableGit (~57 MB zip / 414 MB unpacked). If any git-related command
  inside Claude Code fails on Windows with a "not found" error referring
  to `sh.exe`, `awk`, or other mingw Unix utilities, swap the `GIT_WIN_URL`
  + `GIT_WIN_SHA256` constants in `scripts/build-windows.sh` to the
  `PortableGit-<version>-64-bit.7z.exe` release asset (requires `p7zip-full`
  on the Linux build host for extraction) and rebuild.
