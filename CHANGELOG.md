# Changelog

All notable changes to Raccoon are documented here.
Format: [Keep a Changelog](https://keepachangelog.com) · Versioning: [SemVer](https://semver.org)

## [0.15.1] - 2026-08-25

### Fixed

- The sudo password prompt raised from inside the TUI could not be answered (#23). `rcc apps` asked for it while the TUI held the terminal in raw mode with its own key reader running: raw mode turns off CR-to-newline translation, so pressing Enter never ended sudo's read, and the password came back with whatever was typed next appended to it - "Sorry, try again", every time, on any Mac without Touch ID. Reproduced against a stub sudo that reads a real password: before the fix it received `hunter2qq`, the two keystrokes meant for the TUI swallowed into the read. Root access is now authenticated up front with the terminal released, so no prompt is ever raised underneath the interface, and any script the TUI spawns is told never to prompt. `ensure_sudo` gates its own password path on a reachable `/dev/tty` rather than on stdin being a terminal, which it never is for a spawned script - that mismatch is why the TUI reported "sudo unavailable" and skipped root-only work outright.
- The TUI crashed on its first running frame whenever the terminal reported a width below two, which is what a pty opened without a size reports. Both the running and output views handed `width - 2` straight to `strings.Repeat`, and that panics on a negative count, taking the whole program down with `strings: negative Repeat count`. Separator widths are clamped now.
- The sudo keepalive left its `sleep` behind. Stopping it killed the loop but not the sleep the loop was blocked in, so every run that primed sudo left a process reparented to launchd for up to fifty seconds after `rcc` had exited.
- Quitting the TUI while a script ran did not stop the script. The exit-time kill asserted the wrong model type - the key handlers hand back a pointer - so it never matched, and the script outlived the interface that started it, still holding a primed sudo timestamp.
- `RCC_DRY_RUN` was read as a knob throughout `apps` and `upgrade` but reset to false at the top of both, so exporting it did nothing and `RCC_DRY_RUN=true rcc upgrade` ran for real. An inherited value is honoured now; `--dry-run` still sets it.
- `upgrade` removed its failure log only on the happy path, stranding a `/tmp/raccoon-fail-XXXXXX` behind whenever a run was interrupted.
- The sudo pre-authentication was gated on Homebrew alone. A Mac with a root-owned global npm prefix and no brew never primed a timestamp, so the `sudo -n` behind the npm upgrade could only fail; the same held for the Sparkle install path where `/Applications` is not writable. Both gates ask what actually needs root now.
- `audit` holds a sudo keepalive for the length of a scan. A deep scan can outlive the five-minute timestamp - `softwareupdate` alone takes minutes - and the re-prompt landed mid-report where it could not be answered.
- The TUI asked sudo whether a timestamp was cached from inside its update loop, freezing the interface for as long as that call took. On a Mac whose sudoers comes from a directory service, that is not instant.

## [0.15.0] - 2026-08-18

### Added

- `overlap`: maps every PATH entry to the package manager behind it - brew, npm, cargo, go, pipx, macports, nix - resolving symlinks first. Resolution is the whole point: Homebrew's `bin` entries are relative links into `Cellar`, so an unresolved PATH makes every brew binary look unowned. Two extra categories keep the result readable: `system` for Apple's binaries under SIP (1208 of 2448 entries on the Mac this was written on - no manager installed them, none can remove them), and `shim` for mise/asdf/pyenv/rbenv/nvm/volta, whose per-project shadowing is their job rather than a problem. What survives in `orphan` is the part worth reading: the `curl | sh` scripts and stray `pip install`s that nothing manages any more. One row per PATH entry, not per executable, so broken and circular symlinks are listed and a name shipped by two managers stays two rows. Read-only, and no binary is ever executed - versions belong to manager metadata, so none are reported. `--json` for the machine-readable form.
- CI now runs the `overlap` tests on `ubuntu-latest` as well as macOS. They build their own fake filesystem and never touch the host, so they are the one suite that is meaningful on Linux - enough to catch GNU-vs-BSD drift in `readlink` and `awk` that a macOS-only CI would hide.

### Fixed

- `audit`: a value wider than the report box ran straight through the right border and left the report ragged. `_box_row` padded a short value but did nothing to a long one; two real values were enough here - an IPv6 link-local DNS server and a six-digit quarantined-file count. Long values are now cut and marked with `>`, carrying any trailing colour reset across the truncation.

## [0.14.0] - 2026-08-05

### Added

- `audit`: CIS Benchmark mapping (`--cis`), an HTML report (`--html`), per-check evidence with `--verbose`, `--only` to run a subset of groups, and semantic exit codes so CI can gate on the result.
- `audit`: reports redact secrets **by default** - password/key/token-named values, IPv4 and IPv6 addresses, and MAC addresses. `--no-redact` restores raw output.
- `fleet`: integrity checking, with `--print-bundle` to inspect what is sent.
- `SECURITY.md` and `CONTRIBUTING.md`.

### Fixed

- IPv6 addresses were not redacted in reports (#49). Times (`10:30:45`), zone identifiers (`%en0`) and bracketed hosts (`[::1]:443`) are no longer mangled by the redactor.
- The TUI binary (8.8 MB) was tracked in git; it is untracked now and the repo is correspondingly smaller.

### Changed

- `upgrade`: no longer updates Homebrew **casks**. A bare `brew upgrade` covers formulae *and* casks, so `rcc upgrade` was silently replacing GUI apps despite advertising "package managers and tools" - duplicating `rcc apps`, which already covers every cask via `--greedy`. Both `brew upgrade` and `brew outdated` are now scoped with `--formula`. If you relied on `rcc upgrade` for GUI apps, use `rcc apps`.

### Added

- `upgrade --parallel`: run all twelve tools at once instead of one after another (5.0s → 2.0s on a dry run here). Serial stays the default - this path installs software, so concurrency is opt-in. `--serial` forces the old behaviour and overrides `RCC_PARALLEL=1`. Per-tool output is replayed in the usual order once every tool has finished, rather than as it happens: bash gives each subshell a private copy of the progress counter, so the parent has to own it.

### Fixed

- `upgrade`: reported success no matter what broke. Sixteen pipelines ended in `|| true` and no path ever returned non-zero, so a tool could fail outright and the command still printed "Completed" and exited 0 - a cron job or a piped caller had no way to tell an upgrade from a no-op. Failures are now collected per tool, listed on a `Failed: …` line, and the command exits 1. `npm outdated` keeps its `|| true`: it exits 1 whenever it finds something to update, so treating that as failure would cry wolf every run. Turning this on immediately surfaced three tools failing silently here, one of them Raccoon's own bug (see below).
- `apps`: Sparkle appcasts were fetched one at a time, which dominated the command (16s for 13 feeds here). They are now fetched concurrently - read-only GETs, so nothing installs any faster or in a different order - and a dead feed no longer costs the full 10s, since `--connect-timeout 5` bounds the connect phase separately. Measured 16s → 5.3s. `RCC_FETCH_JOBS` (default 8) caps the concurrency.
- `apps`: the ~16MB Homebrew cask catalog was re-downloaded on every run. It is now cached in `~/.raccoon/cask-catalog.json` for a day, written atomically so an interrupted download cannot leave a truncated cache behind. Measured 5.3s → 3.5s per run, plus 16MB of traffic saved each time. `--no-catalog` still skips the layer entirely.

## [0.13.4] - 2026-06-28

### Fixed

- `fleet remove`: matched hosts by substring, so `remove user@192.168.1.1` also deleted `user@192.168.1.10` (and any line containing that text). Now matches whole lines.
- `fleet scan`: hosts that need `ssh-copy-id` were silently dropped - under `set -e` a failed probe `ssh` aborted before it could report "setup needed". Those hosts are reported again.
- `fleet scan`: could run for minutes with no output on a busy network. Probes now run fully in parallel under a per-host timeout and an overall `SCAN_MAX` budget (default 45s, env-overridable), and it prints how many hosts it is probing.
- `fleet scan` / `run` / `audit`: a background timeout killing `ssh` leaked a shell "Terminated" job message into stdout/JSON; suppressed without losing `ssh`'s own output.
- `fleet run`: quoted multi-word arguments were flattened (`grep "a b"` → `grep a b`); arguments are now preserved with `printf %q`. Added a per-command timeout and a temp-dir cleanup trap.
- `fleet audit`: a truncated remote JSON response could abort the whole aggregation; the parse now falls back to zero.
- `fleet audit` / `run`: a non-numeric or zero `--parallel` value crashed or spun; it is now validated.
- `fleet`: an unknown subcommand now exits non-zero; `fleet add` / `remove` no longer print Italian strings; `fleet group list` pluralizes "host(s)".

## [0.13.3] - 2026-06-27

### Fixed

- `apps`: outdated GUI apps were detected but often not updated. Three causes in the Homebrew-catalog layer:
  - Casks with a built-in auto-updater (`auto_updates`) were skipped, deferring to the app's own - frequently stale - updater. They are now updated via `brew install --cask --force` by default, matching `brew --greedy`. `--auto-launch` becomes opt-in to instead open the app so its internal updater runs.
  - The catalog version was parsed with a greedy regex that grabbed the last `version` on the line - an older fallback inside per-OS `variations` blocks (e.g. VS Code read as 1.97.2 instead of 1.126.0), so the installed copy looked newer and was skipped as up to date. Now reads the top-level version. Never downgrades.
  - `pkg`/installer casks ship no `app` artifact and were dropped from the lookup entirely; they are now matched by the cask display name, recovering Microsoft Teams / Multipass-class apps. Pure awk, no new dependency.
- `apps`: trim the `,revision` suffix from cask versions in the displayed output.

## [0.13.2] - 2026-06-26
### Added
- TUI: fleet entries in the interactive menu (scan, audit, status, list, groups).
  Argument-heavy subcommands (`run`, `group add`, `audit --group`) remain CLI-only.

## [0.13.1] - 2026-06-26
### Added
- `fleet scan` - discover Macs on the LAN (Bonjour + ping-sweep) and classify each host as ready / setup-needed / non-Mac; `--add` (or an interactive prompt) appends the fleet-ready hosts to `fleet.conf`. Options: `--user`, `--subnet`, `--timeout`, `--json`.
- `fleet group add|remove|list` - named groups of already-added hosts (`~/.raccoon/fleet-groups.conf`).
- `fleet run [--group NAME] [--parallel N] -- COMMAND` - run a command over SSH on every host, or just one group, in parallel.
- `fleet audit --group NAME` - audit only the hosts in a group.
### Fixed
- `apps`: Sparkle update detection now reads the latest appcast `<item>` and compares like-for-like (marketing version vs `shortVersionString`, or build vs `sparkle:version`). Apps that auto-update and are installed outside Homebrew (e.g. Arc, IINA) are detected correctly instead of being mis-compared against build numbers or skipped.
### Changed
- All user-facing output is now in English.

## [0.12.0] - 2026-06-25
### Added
- `audit --explain` - plain-language notes for each check.
- `audit --remediation` - before/after report for MSP technicians.
- `startup --clean` - interactively remove orphaned LaunchAgents (with backup).
- First-run onboarding wizard.
- `wifi` - active network, known SSIDs, opt-in Keychain passwords.
- `audit --baseline` / `--baseline-diff` / `--baseline-reset` - reference-state monitoring.
- `audit --schedule daily|weekly|monthly` (+ `status`/`remove`); native macOS alerts via `--alert`.
- Audit health-history sparkline in the menu banner.
- `disk --large` (`--min`, `--top`) - biggest files.
- `audit --profile` - per-client config, branding, and baseline.
- `audit --share` - publish the report as an anonymous GitHub Gist.
- `audit --sheet` (`--hours`, `--notes`) - fill-in intervention sheet (Markdown/RTF).
- `fleet` - SSH audit across multiple Macs (`audit`/`status`/`add`/`remove`/`list`); the remote runs a self-contained bundle, so no install is needed on the remote Macs.
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
