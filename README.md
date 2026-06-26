
<p align="center">
  <img src="docs/gifs/hero.gif" alt="Raccoon — rcc audit running" width="800">
</p>

# 🦝 Raccoon

> **Security audits, system info & SSH fleet management for macOS.**
> *For the people who maintain Macs they don't sit in front of — and need to show their work.*

[![CI](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/thousandflowers/Raccoon?sort=semver&color=blue)](https://github.com/thousandflowers/Raccoon/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)
![Bash](https://img.shields.io/badge/shell-bash%203.2%2B-4EAA25?logo=gnubash&logoColor=white)
![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)
![Tests](https://img.shields.io/badge/tests-bats-blue)
[![Last commit](https://img.shields.io/github/last-commit/thousandflowers/Raccoon)](https://github.com/thousandflowers/Raccoon/commits/main)
[![git clones](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/thousandflowers/Raccoon/main/.github/traffic/clones.json&cacheSeconds=1800)](https://github.com/thousandflowers/Raccoon/graphs/traffic)
[![Homebrew tap](https://img.shields.io/badge/brew%20tap-thousandflowers%2Fraccoon-FBB040?logo=homebrew&logoColor=white)](https://github.com/thousandflowers/homebrew-raccoon)

Zero dependencies beyond macOS + git. ~1500 lines of shellcheck-clean Bash, covered by a comprehensive bats suite. Runs on the system Bash (3.2 → 5.x) — no Homebrew required.

---

## Why I built this

It started as a PR to [Mole](https://github.com/tw93/Mole): a `mo update` that bumped brew, pip, npm, and gem in one shot. The maintainer liked it but declined it as out of scope.

So I merged it with the script I already ran on my sisters' Macs — disk space, open ports, startup items — and kept adding commands. It now writes client reports and audits a room of Macs over SSH, but it's still the same tool: just the things I needed.

---

## Contents

- [Install](#install)
- [What you can do](#what-you-can-do)
- [Fleet management](#️-fleet-management)
- [All commands](#all-commands)
- [Why Raccoon is different](#why-raccoon-is-different)
- [Is it safe to pipe to `bash`?](#is-it-safe-to-pipe-to-bash)
- [Go TUI](#go-tui)
- [Shell completion](#shell-completion) · [Man page](#man-page) · [Project structure](#project-structure) · [Contributing](#contributing)

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Or via Homebrew:

```bash
brew install thousandflowers/raccoon/rcc
```

Run `rcc` to launch the interactive [menu](#go-tui), or `rcc <command>` for direct access.

<details>
<summary>Update &amp; uninstall</summary>

**Update:**

```bash
brew upgrade rcc                                                                   # Homebrew
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash   # curl install
```

**Uninstall:**

```bash
brew uninstall rcc                          # Homebrew
rm -rf ~/.raccoon && rm "$(which rcc)"      # curl install
```
</details>

---

## Requirements

- **macOS** on Apple Silicon or Intel, with the built-in `bash` (3.2+) — nothing extra to install for the core commands.
- **git** — used by the curl installer and by `rcc git`.
- **Optional, per command:** `mas` (App Store updates in `rcc apps`), `gpg` (`rcc ssh --export-gpg`), `docker` (`rcc docker`), Homebrew (`rcc upgrade` / `apps`), and Go (only to build the TUI).

---

## What you can do

### 🔒 Security audit

```bash
rcc audit                 # 30+ security checks (Gatekeeper, firewall, SIP, sharing…)
rcc audit --fix           # apply safe fixes — every change is backed up first
rcc audit --deep          # add slower, deeper checks
rcc audit --json          # machine-readable output (also: --csv, --report file.md)
rcc audit --baseline      # snapshot now; later runs diff against it
```

Per-client reports with `--client`, `--shop`, `--tech` and reusable profiles
(`rcc audit --profile mario-bianchi`). `--fix` backs every change up to
`~/.raccoon/fix-backups/<timestamp>/` first, and schedules itself with
`rcc audit schedule weekly` (LaunchAgent).

```
$ rcc audit
  Security Audit · 2026-06-26 14:30

  ✓ FileVault            Enabled
  ✓ Gatekeeper           Enabled
  ✓ SIP                  Enabled
  ⚠ Firewall             On — stealth mode off
  ✓ Screen Lock          Locks immediately
  ⚠ Sharing              Remote Login (SSH) enabled
  ✗ Software Updates     3 updates pending
  …
  ────────────────────────────────────────────
  28 passed · 3 warnings · 1 failed
  Run `rcc audit --explain` for the why behind each finding
```

![audit](docs/gifs/rcc-audit.gif)

<details>
<summary>What gets checked (30+)</summary>

- **System:** FileVault, SIP, Gatekeeper, XProtect, Firewall, Stealth Mode, Software Updates, Screen Lock, Auto-Login
- **Network:** Sharing, Open Ports, SSH Daemon, DNS Servers, DNS-over-HTTPS, VPN, Bluetooth
- **Auth & keys:** Keychain, SSH Keys, `.ssh` permissions, Authorized Keys, Sudo Access, Sudoers
- **Persistence:** Login Items, Cron Jobs, At Jobs, LaunchDaemons, System & User LaunchAgents, Kernel Extensions
- **Privacy:** Location Services, Analytics, Quarantined Files

</details>

<details>
<summary>Client-facing report (<code>--report report.md</code>)</summary>

`rcc audit --client "Jane Doe" --shop "MacFix Pro" --tech "Mario Rossi" --report report.md`
produces a branded intervention sheet (also `--report report.rtf` for Pages/Word):

```markdown
# Intervention Sheet

**Date:** 2026-06-26
**Technician:** Mario Rossi
**Client:** Jane Doe — MacFix Pro

## Issues found and resolved

| Check            | Before      | After      |
|------------------|-------------|------------|
| Firewall         | Off         | On         |
| Software Updates | 3 pending   | Installed  |
| Remote Login     | Enabled     | Disabled   |

**Hours worked:** 0.5

_Generated by Raccoon_
```
</details>

### 🛰️ Fleet management

Discover, group, run commands on, and audit every Mac you manage — from one
machine, over SSH, in parallel:

```bash
rcc fleet scan                         # discover Macs on the LAN (Bonjour + ping-sweep)
rcc fleet add mario@192.168.1.10       # ...or add hosts by hand
rcc fleet group add office mario@192.168.1.10 luca@192.168.1.11   # organize into groups
rcc fleet run --group office -- softwareupdate -l                 # run a command in bulk
rcc fleet audit                        # security-audit every host, one aggregate report
rcc fleet audit --group office --report office.md
rcc fleet status                       # quick reachability check
```

`rcc fleet scan` classifies each host it finds as **ready** (key auth works),
**setup-needed** (SSH up, needs `ssh-copy-id`), or **non-Mac**, and can append the
ready ones to your host list. Hosts live in `~/.raccoon/fleet.conf` (one
`user@host[:port]` per line, key auth only). **Remote Macs don't need Raccoon
installed** — the audit script is streamed over SSH stdin to `bash`, so they need
only bash, macOS, and an SSH server.

### 🖥️ System information

```bash
rcc disk                  # internal, external & network drives, SMART
rcc disk large            # biggest files (--min SIZE, --top N)
rcc network               # interfaces, Wi-Fi, DNS, routing
rcc wifi                  # active network, known SSIDs, Keychain passwords
rcc memory                # system stats + processes sorted by RAM
rcc ports                 # open ports & listening services
rcc battery               # health %, cycles, temperature
rcc backup                # Time Machine status
```

### 🧹 Maintenance

```bash
rcc env                   # shell environment & PATH breakdown
rcc startup               # launch agents & login items
rcc startup clean         # remove orphaned launch agents (interactive)
rcc trash                 # trash size & empty
rcc fonts                 # find duplicates & corrupted fonts
rcc history               # shell history analysis
rcc certs                 # SSL certificate expiry report
```

### 🛠️ Developer tools

```bash
rcc upgrade               # update brew, pip, npm, gem… at once (--dry-run to preview)
rcc apps                  # update GUI apps in 4 layers (see below)
rcc ssh                   # inspect keys, --export, --export-gpg
rcc git                   # status, branches, stash, cleanup
rcc docker                # images, containers, volumes
rcc xcode                 # simulators, derived data, SPM caches
```

`rcc apps` updates in four layers, in order: Mac App Store (`mas`), Homebrew
casks (`--greedy`), the Homebrew cask catalog (7000+ apps matched to
`/Applications` by name — no install required, parsed with pure awk), and
Sparkle feeds (apps with a `SUFeedURL` in their plist). Apps with built-in
auto-updaters are detected and skipped by default; `--auto-launch` opens them
to trigger their own updater. Skip a layer with `--no-catalog` / `--no-sparkle`.

<details>
<summary>📸 More command demos</summary>

**System info**

![disk](docs/gifs/rcc-disk.gif)
![network](docs/gifs/rcc-network.gif)
![memory](docs/gifs/rcc-memory.gif)
![ports](docs/gifs/rcc-ports.gif)
![battery](docs/gifs/rcc-battery.gif)
![backup](docs/gifs/rcc-backup.gif)

**Developer tools**

![upgrade](docs/gifs/rcc-upgrade.gif)
![docker](docs/gifs/rcc-docker.gif)
![git](docs/gifs/rcc-git.gif)
![xcode](docs/gifs/rcc-xcode.gif)
![certs](docs/gifs/rcc-certs.gif)

**Maintenance**

![env](docs/gifs/rcc-env.gif)
![startup](docs/gifs/rcc-startup.gif)
![trash](docs/gifs/rcc-trash.gif)
![fonts](docs/gifs/rcc-fonts.gif)
![history](docs/gifs/rcc-history.gif)

</details>

---

## All commands

<details>
<summary>Full command reference</summary>

| Command | What it does |
|---------|--------------|
| `audit` | 30+ security checks; `--fix`, `--deep`, `--json`/`--csv`, `--report`, `--baseline`, `--profile`, `schedule` |
| `fleet` | `scan`, `add`/`remove`/`list`, `group`, `run`, `audit`, `status` across many Macs over SSH |
| `disk` | Internal/external/network drives, SMART; `disk large` for biggest files |
| `network` | Interfaces, Wi-Fi, DNS, routing |
| `wifi` | Active network, known SSIDs, Keychain passwords |
| `memory` | System memory + processes by RAM |
| `ports` | Open ports & listening services |
| `battery` | Health %, cycles, temperature |
| `backup` | Time Machine status |
| `env` | Shell environment & PATH breakdown |
| `startup` | Launch agents & login items; `startup clean` |
| `trash` | Trash size & empty |
| `fonts` | Duplicate & corrupted fonts |
| `history` | Shell history analysis |
| `certs` | SSL certificate expiry report |
| `upgrade` | Update brew/pip/npm/gem…; `--dry-run` |
| `apps` | Update GUI apps in 4 layers |
| `ssh` | Inspect/export keys |
| `git` | Status, branches, stash, cleanup |
| `docker` | Images, containers, volumes |
| `xcode` | Simulators, derived data, SPM caches |

</details>

---

## Why Raccoon is different

- **Safe by default, not silent by default.** `--fix` backs up every destructive change to `~/.raccoon/fix-backups/<timestamp>/` before touching anything — a wrong fix is always recoverable.
- **No install on the remote Macs.** Fleet mode streams the audit over SSH stdin; remote machines need only bash, macOS, and an open SSH server.
- **Auditable, not opinionated.** It never sets a public DNS resolver or strips Gatekeeper quarantine flags — both would silently weaken a working setup.
- **One data model.** Text, JSON, CSV, Markdown, RTF, and the fleet aggregate all render from the same `AUDIT_RESULTS` array, so a new check shows up everywhere automatically.

---

## Is it safe to pipe to `bash`?

Fair question for a tool that audits security and runs `sudo`. The honest answer:

- **Read it first.** The installer is one file — [`install.sh`](install.sh). It clones the repo to `~/.raccoon` and symlinks `rcc`; nothing else. Prefer Homebrew (`brew install thousandflowers/raccoon/rcc`) if you'd rather not pipe to a shell.
- **No telemetry.** Raccoon makes no analytics or "phone-home" calls. Ever.
- **Network calls are only the obvious ones:** `apps` fetches the Homebrew cask catalog and Sparkle appcasts to update apps; `audit --share` (opt-in only) uploads a report to GitHub; `fleet` connects over SSH to *your* hosts and uses Bonjour/ping on *your* LAN for `scan`; `upgrade` talks to the package managers you already use. Nothing leaves your machine unless you run one of those.
- **`sudo` only when it's doing the work** — applying `audit --fix` changes or installing a cask — never just to look around.
- **Reports can contain sensitive data** — open ports, hostnames, SSH keys, and (via `rcc wifi`) Keychain Wi-Fi passwords. Review any report before you share it.
- **Auditable.** ~1500 lines of plain Bash, `shellcheck -S warning` clean, covered by a comprehensive bats suite. Read any command in [`bin/`](bin/).

---

## Go TUI

Raccoon ships an optional terminal UI built with [Bubble Tea](https://github.com/charmbracelet/bubbletea):

```
┌────────────────────────────────────────────────┐
│ Raccoon                                          │
│ macOS companion toolkit                          │
│                                                  │
│ upgrade       audit        network               │
│ fleet scan    fleet audit  fleet status          │
│ fleet list    fleet groups                       │
│ disk          memory       ssh         git       │
│ ports         battery      backup      env       │
│ startup       trash        fonts       history   │
│ certs         docker       xcode                 │
│                                                  │
│ ←→ Navigate · ↑↓ Rows · / Search · Enter Run     │
└────────────────────────────────────────────────┘
```

Compile with `cd ui && ./build.sh`. The binary lands in `bin/rcc-ui` and is
auto-detected by `rcc`. Argument-heavy fleet subcommands (`run`, `group add`,
`audit --group`) stay on the CLI, where you can pass them.

---

## Shell completion

```bash
rcc completion bash >> ~/.bashrc      # or: rcc completion zsh >> ~/.zshrc
```

## Man page

```bash
man rcc      # every command, flag, and example
```

## Project structure

```
Raccoon/
├── rcc                  # Entry point + dispatcher
├── install.sh           # curl | bash installer
├── lib/core/            # Shared shell library (common.sh, commands.sh)
├── bin/                 # Command scripts (audit, fleet, disk, …)
├── ui/                  # Go Bubble Tea TUI
├── completions/         # bash + zsh autocompletions
├── man/man1/rcc.1       # Man page
├── tests/               # Bats test suite
└── docs/                # Images, GIFs, guides
```

## Contributing

Bug reports and PRs welcome — use the templates.

```bash
brew install bats-core shellcheck
bats tests/                              # run tests
shellcheck rcc bin/*.sh lib/core/*.sh    # lint
```

---

## License

MIT — see [LICENSE](LICENSE).
