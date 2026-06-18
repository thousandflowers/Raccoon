<div align="center">

<img src="docs/gifs/rcc-menu.gif" alt="Raccoon security audit" width="700">

# 🦝 Raccoon

### The macOS companion toolkit for power users

**One CLI for security audits, hardware health, network state, package hygiene, and dev workflows — with an optional TUI.**

[![CI](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/thousandflowers/Raccoon?sort=semver)](https://github.com/thousandflowers/Raccoon/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-black.svg)](#)
[![Made with Bash](https://img.shields.io/badge/made%20with-Bash-1f425f.svg)](#)
[![Stars](https://img.shields.io/github/stars/thousandflowers/Raccoon?style=social)](https://github.com/thousandflowers/Raccoon/stargazers)

`32 security checks` · `zero dependencies` · `1500+ lines of shellcheck-clean shell`

</div>

---

```bash
brew install thousandflowers/raccoon/rcc
rcc audit
```

That's it. No 500MB app, no background daemons, no splash screens — just `rcc <command>` and results.

---

## Why Raccoon?

Most Mac maintenance means juggling a dozen tools: a security scanner here, a battery checker there, four package managers to update by hand. Raccoon (`rcc`) folds all of it into one fast, auditable CLI that ships with macOS-native Bash.

|  | Raccoon | Proprietary "cleaner" apps | Scattered scripts |
| --- | :---: | :---: | :---: |
| Security audit (32 checks) | ✅ | partial | ❌ |
| Hardware + network diagnostics | ✅ | partial | ❌ |
| Tracks brew / pip / npm / gem in one command | ✅ | ❌ | ❌ |
| Zero dependencies beyond stock macOS | ✅ | ❌ (500MB+) | ✅ |
| Open source & auditable | ✅ | ❌ | ✅ |
| No background daemons / telemetry | ✅ | ❌ | ✅ |
| Optional TUI | ✅ | ✅ | ❌ |

**Built on three principles:**

- **Portable** — almost entirely Bash, zero dependencies beyond what ships with macOS + git.
- **Fast** — no splash screens, no daemons, no telemetry. Just results.
- **Trustworthy** — 1500+ lines of shell, all `shellcheck`-clean and CI-verified.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Install with Homebrew](#install-with-homebrew)
- [Install with curl](#install-with-curl)
- [Usage & Examples](#usage--examples)
- [Commands](#commands)
- [Go TUI](#go-tui)
- [Security Audit](#security-audit)
- [Shell Completion](#shell-completion)
- [Man Page](#man-page)
- [Contributing](#contributing)
- [Updating](#updating)
- [Uninstall](#uninstall)
- [Project Structure](#project-structure)
- [License](#license)

---

## Quick Start

The fastest way to get started — install via Homebrew and run your first audit:

```bash
brew install thousandflowers/raccoon/rcc
rcc audit
```

Run `rcc` for the interactive menu or `rcc <command>` for direct access.


---

## Install with Homebrew

**Recommended.** The Homebrew formula handles versioning, upgrades, and uninstallation automatically — no symlinks to manage.

```bash
brew install thousandflowers/raccoon/rcc
```

This adds the [homebrew-raccoon](https://github.com/thousandflowers/homebrew-raccoon) tap automatically. After that:

```bash
rcc audit                # run a quick security audit
brew upgrade rcc         # update to the latest version
brew uninstall rcc       # remove completely
```

---

## Install with curl

For single-user setups without Homebrew:

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Clones to `~/.raccoon`, symlinks `rcc` to `/usr/local/bin`. Run `rcc` for the interactive menu or `rcc <command>` for direct access.

---

## Usage & Examples

```bash
rcc [command] [options]
```

Run `rcc` with no arguments → interactive menu. Pass a command for direct access.

<img src="docs/gifs/rcc-menu.gif" alt="rcc interactive menu" width="700">

**Quick checks:**

```bash
rcc audit            # 32-point security scan
rcc disk             # internal, external & network drives, SMART
rcc network          # Interfaces, Wi-Fi, DNS, routing table
rcc battery          # Health %, cycle count, temperature
rcc upgrade          # Brew + pip + npm + gem — tracked metrics
```

**Flag style — two forms accepted:**

```bash
rcc audit deep       # classic
rcc audit --deep     # flag style — same result
```

All audit flags work both ways: `--json` / `json`, `--fix` / `fix`, `--history` / `history`.

<div align="center">
<img src="docs/gifs/rcc-audit.gif" alt="rcc audit" width="48%">
<img src="docs/gifs/rcc-battery.gif" alt="rcc battery" width="48%">
</div>

---

## Commands

| Command | Description |
| --- | --- |
| **Core Tools** | |
| `upgrade` | Update Homebrew, pip, npm, gem |
| `upgrade --dry-run` | Show what would be upgraded without updating |
| `audit` | Security audit (32 checks) |
| `audit deep` | Full audit (requires sudo) |
| `audit fix` | Auto-fix common security issues |
| `audit json` | Audit output in JSON format |
| `audit history` | Audit history with diff |
| `audit watch` | Schedule weekly audit via LaunchAgent |
| **System** | |
| `network` | Interfaces, Wi-Fi, DNS, routing |
| `disk` | Internal, external & network drives, SMART |
| `memory` | System stats (cached, swap) + processes by RSS |
| `ports` | Open ports and listening services |
| `battery` | Battery health, cycles, temperature |
| `backup` | Time Machine status |
| **Developer** | |
| `ssh` | Key inspection, `--export`, `--export-gpg` |
| `git` | Git status, branches, stash, cleanup |
| `docker` | Images, containers, volumes |
| `xcode` | Simulators, derived data, SPM |
| **Maintenance** | |
| `env` | Shell environment and PATH summary |
| `startup` | Launch agents and login items |
| `trash` | Trash contents and size |
| `fonts` | Font duplicates and corruption |
| `history` | Shell history analysis |
| `certs` | SSL certificates and expiration |
| **Meta** | |
| `--version`, `-V` | Print version |
| `help`, `--help`, `-h` | Show help |

---

## Go TUI

When compiled, Raccoon launches a [Bubble Tea](https://github.com/charmbracelet/bubbletea) TUI instead of the Bash fallback menu:

```
┌──────────────────────────────────────────────┐
│ Raccoon                                        │
│ macOS companion toolkit                        │
│                                                │
│ upgrade    audit      network    disk          │
│ memory     ssh        git        ports         │
│ battery    backup     env        startup       │
│ trash      fonts      history    certs         │
│ docker     xcode                               │
│                                                │
│ ←→ Navigate · ↑↓ Rows · Enter Run · Q Quit     │
└──────────────────────────────────────────────┘
```

Build it:

```bash
cd ui && ./build.sh
```

The binary is compiled to `bin/rcc-ui` (a universal arm64 + amd64 binary) and auto-detected by the `rcc` entrypoint.

---

## Security Audit

Raccoon runs **32 checks** across Core Security, Network, Auth, Persistence, Privacy, and more.

| Flag | Description |
| --- | --- |
| `--deep` | All 32 checks (requires sudo) |
| `--quiet` | Output just "pass warn fail" counts |
| `--json` | JSON format |
| `--csv` | CSV format |
| `--html` | HTML report |
| `--report FILE` | Save report to file |
| `--fix` | Auto-fix issues where possible |
| `--fix --dry-run` | Show what would be fixed |
| `--fix --force` | Skip confirmation |
| `--history` | Show audit history |
| `--diff` | Changes since last audit |
| `--watch` | Weekly scheduled audit |
| `--notify` | Send notification on completion |

History is saved to `~/.raccoon/audit-history/`; the last 30 runs are kept automatically.

---

## Shell Completion

Install completion for the current shell:

```bash
# Bash
source <(rcc completion bash)

# Zsh
source <(rcc completion zsh)
```

To make it permanent, add the matching line to `~/.bashrc` or `~/.zshrc`. Completions cover all commands, flags, and audit subcommands (`deep`, `fix`, `json`, `history`, etc.).

---

## Man Page

```bash
man rcc
```

Covers all commands, flags, and examples. The installer symlinks it into `/usr/local/share/man/man1/rcc.1`. To read without installing:

```bash
nroff -man man/man1/rcc.1 | less
man -l man/man1/rcc.1
```

---

## Contributing

Bug reports and PRs welcome. Please use the issue/PR templates:

- [Bug report](.github/ISSUE_TEMPLATE/bug_report.md)
- [Feature request](.github/ISSUE_TEMPLATE/feature_request.md)
- [Pull request template](.github/PULL_REQUEST_TEMPLATE.md)

**Running tests:**

```bash
brew install bats-core      # if needed
bats tests/                 # full suite
bats tests/test_audit.bats  # single file
```

**Style:** All shell scripts pass `shellcheck`. Run before pushing:

```bash
shellcheck rcc install.sh bin/*.sh lib/core/*.sh
```

---

## Updating

```bash
brew upgrade rcc                                                                       # Homebrew (recommended)
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash   # curl
cd ~/.raccoon && git pull                                                              # manual
```

---

## Uninstall

```bash
# Homebrew
brew uninstall rcc
brew untap thousandflowers/raccoon   # optional — removes the tap

# curl | bash
rm -rf ~/.raccoon
rm "$(which rcc)"
```

---

## Project Structure

```
Raccoon/
├── rcc                 # Entry point + dispatcher
├── install.sh          # One-line installer
├── man/man1/rcc.1      # Man page
├── ui/                 # Go Bubble Tea TUI (main.go, build.sh)
├── bin/                # Diagnostic scripts (audit.sh = 896-line audit engine, +17 more)
├── lib/core/           # Shared library (common.sh, commands.sh)
├── completions/        # Shell autocompletion (bash + zsh)
├── tests/              # Bats test suite (18 tests for the audit engine alone)
└── .github/            # CI (shellcheck + Go build + bats), templates, dependabot
```

---

## License

MIT — see [LICENSE](LICENSE).

<div align="center">

**If Raccoon saved you a few minutes, consider leaving a ⭐ — it genuinely helps.**

Made with 🦝 by [thousandflowers](https://github.com/thousandflowers)

</div>
