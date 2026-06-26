# Changelog

All notable changes to Raccoon are documented here.
Format: [Keep a Changelog](https://keepachangelog.com) · Versioning: [SemVer](https://semver.org)

## [0.13.0] - 2026-06-26
### Added
- `fleet scan` — discover Macs on the LAN (Bonjour + ping-sweep) and classify each host as ready / setup-needed / non-Mac; `--add` (or an interactive prompt) appends the fleet-ready hosts to `fleet.conf`. Options: `--user`, `--subnet`, `--timeout`, `--json`.
- `fleet group add|remove|list` — named groups of already-added hosts (`~/.raccoon/fleet-groups.conf`).
- `fleet run [--group NAME] [--parallel N] -- COMMAND` — run a command over SSH on every host, or just one group, in parallel.
- `fleet audit --group NAME` — audit only the hosts in a group.
### Fixed
- `apps`: Sparkle update detection now reads the latest appcast `<item>` and compares like-for-like (marketing version vs `shortVersionString`, or build vs `sparkle:version`). Apps that auto-update and are installed outside Homebrew (e.g. Arc, IINA) are detected correctly instead of being mis-compared against build numbers or skipped.
### Changed
- All user-facing output is now in English.

## [0.12.0] - 2026-06-25
### Added
- `audit --explain` — plain-language notes for each check.
- `audit --remediation` — before/after report for MSP technicians.
- `startup --clean` — interactively remove orphaned LaunchAgents (with backup).
- First-run onboarding wizard.
- `wifi` — active network, known SSIDs, opt-in Keychain passwords.
- `audit --baseline` / `--baseline-diff` / `--baseline-reset` — reference-state monitoring.
- `audit --schedule daily|weekly|monthly` (+ `status`/`remove`); native macOS alerts via `--alert`.
- Audit health-history sparkline in the menu banner.
- `disk --large` (`--min`, `--top`) — biggest files.
- `audit --profile` — per-client config, branding, and baseline.
- `audit --share` — publish the report as an anonymous GitHub Gist.
- `audit --sheet` (`--hours`, `--notes`) — fill-in intervention sheet (Markdown/RTF).
- `fleet` — SSH audit across multiple Macs (`audit`/`status`/`add`/`remove`/`list`); the remote runs a self-contained bundle, so no install is needed on the remote Macs.
### Changed
- `audit --json --quiet` now emits clean JSON (powers fleet mode); `print_output_json` includes the per-check `results` array.
- The bash fallback menu is data-driven; assorted internal de-duplication.

## [0.11.1] - 2026-06-23
### Fixed
- `apps`: pre-cache sudo so cask upgrades don't garble the password prompt.
- `apps`: suppress `mas` Spotlight warnings that flooded the output.
### Changed
- Regenerated demo GIFs (Remotion, synthetic and PII-free) and optimized their file sizes.

## [0.11.0] - 2026-06-22
### Added
- `audit --fix`: destructive fixes (SSH `authorized_keys`, cron, LaunchAgents, login items) now snapshot the originals to `~/.raccoon/fix-backups/<timestamp>/` first.
- Per-machine opt-out: list check names in `~/.raccoon/audit.conf` to report-but-never-fix them.
- `lib/audit/checks.sh` is now shellcheck-linted in CI.
### Changed
- `audit --fix` is safe by default: dropped the auto-set of Google DNS (a DHCP-provided resolver is now reported as a pass) and the recursive `com.apple.quarantine` strip (report-only, so Gatekeeper is preserved).
### Fixed
- APFS disk/memory crashes, TUI progress abort, and hidden sudo prompt (#23, #24).
- Failed fixes now surface their error instead of failing silently.
- ~40 bugs across a full-repo audit (shell + Go TUI).

## [0.10.3] - 2026-06-19
### Fixed
- CI version detection is robust under `pipefail` with a dynamic VERSION.
- Guard `git describe` to avoid a Homebrew tag leak.

## [0.10.2] - 2026-06-19
### Added
- `apps` entry in the interactive TUI menu.
### Fixed
- `audit`: correct `softwareupdate` parsing for modern macOS.

## [0.10.1] - 2026-06-19
### Fixed
- CI: use the `RACCOONTAPPUSH` secret and make releases idempotent.
- Derive the version from the git tag.

## [0.10.0] - 2026-06-19
### Added
- `rcc apps`: update both Mac App Store and non-App-Store applications.
### Changed
- UI improvements, especially for `rcc update` and `rcc audit`.
### Fixed
- Various audit fixes.

## [0.9.1] - 2026-06-18
### Added
- `upgrade`: tap-trust preflight; support for pnpm, bun, uv, Go, Docker, and claude; npm sudo fallback.
- `backup`: Time Machine destination mount-point display and exclusion handling.
- `disk`: MOUNT POINT column, dynamic `/Volumes/*` scan, internal/external classification.
### Fixed
- Test teardown runs `chmod -R +w` before `rm -rf` to handle read-only `go install` files.

## [0.9.0] - 2026-06-18
### Added
- `disk`: network-mounts section (smbfs/nfs/afpfs) and external-drive detection.
- `memory`: system RAM stats (wired, active, cached, compressed, swap).
- `ssh`: `--export` (copy public key to clipboard) and `--export-gpg`.
### Fixed
- GUI hang: child processes no longer inherit TTY raw mode.

## [0.8.0] - 2026-06-12
### Changed
- Split the monolithic `audit.sh` into plumbing plus `lib/audit/checks.sh`.
### Fixed
- bash 3.2 resilience: `|| true` fallback on sudo/command substitutions under `set -euo pipefail`; non-interactive audit now exits 0 instead of crashing.

## [0.7.0] - 2026-06-09
### Fixed
- Restored the v0.5.0 animated Bubble Tea TUI (v0.6.x had replaced it with a plain-grid draft).
- `rcc --version` now reports the real version.
### Changed
- TUI palette contrast raised for dark terminals.

## [0.6.1] - 2026-06-09
### Fixed
- `audit`: category box right-border padding (SC2154); removed dead `CURRENT_CATEGORY` (SC2034).
- `install.sh`: use `fetch + reset` instead of `git pull` so installs survive force-pushes.

## [0.6.0] - 2026-06-08
### Added
- bash/zsh completions, man page, install script, bats suite (14 tests), CI workflow, issue/PR templates, and LICENSE.
### Fixed
- All shellcheck warnings across `bin/` and `lib/core/`.
- Non-interactive sudo guard in `audit.sh` (no more hang on the sudo prompt).

## [0.5.0] - 2026-06-07
### Added
- Animated TUI: per-script raccoon animations and a real-time progress bar.
### Changed
- bash 3.2 compatibility.

## [0.2.5] - 2026-04-29
### Added
- `trash --empty` with a confirmation prompt.
### Fixed
- `startup`: launch-agent name parsing and uptime column overflow.
- `env`: duplicate PATH detection.
- `fonts`: variable scope when computing totals.

## [0.2.4] - 2026-04-29
### Fixed
- `startup`: launch-agent prefix stripping and load-average extraction.
- `fonts`: duplicate sections and total-row placement.
- `history`: zsh extended-history parsing.
- `docker`: placeholders for empty columns.

## [0.2.3] - 2026-04-29
### Added
- Progress labels across `fonts`, `trash`, `backup`, and `certs`.
### Fixed
- Table alignment via shared helpers in `startup`, `docker`, and `history`.
- `env`: summary line and symlink check.
- `audit`: `while/shift` argument parsing and correct `--report FILE`.

## [0.2.2] - 2026-04-29
### Added
- All 18 `bin/*.sh` scripts and the `ui/` directory to the public repo.
- `upgrade`: inline spinner for long operations.
### Fixed
- `rcc`: removed `exec` so the bash fallback menu triggers when the Go UI fails.
- `memory`: JSON trailing comma.
- `common`: removed dead table functions.

## [0.2.1] - 2026-04-29
### Added
- `ui/build.sh` to compile `rcc-ui`; install compiles it when Go is present.
### Fixed
- Table alignment in `disk`/`memory`; `memory --top N` parsing.
- `rcc audit` multi-word subcommands (`fix`, `deep`).
- Audit category header padding and auto-fix prompt reliability.

## [0.2.0] - 2026-04-29
### Added
- Interactive auto-fix prompt after the audit summary, plus a `MANUAL:` fix pattern.
- All commands wired into `rcc` (audit variants, network, disk, memory, and more).
### Fixed
- rcc-ui terminal corruption via `tea.ExecProcess`; table alignment; four failing auto-fix actions.

## [0.1.0] - 2026-04-28
### Added
- Initial release: `rcc audit` (quick and `--deep`), output formats (`--json`/`--csv`/`--html`), `certs`, and an interactive menu.
