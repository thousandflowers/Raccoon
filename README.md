# 🦝 Raccoon

> macOS companion toolkit for power users

[![CI](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Go](https://img.shields.io/badge/Go_TUI-Bubble_Tea-00ADD8?logo=go)](ui/)

Raccoon (`rcc`) is a system diagnostics and maintenance toolkit for macOS. It surfaces security audits, hardware health, network state, package hygiene, and developer workflows through a single CLI — with an optional [Bubble Tea](https://github.com/charmbracelet/bubbletea) TUI.

- **Zero dependencies** beyond stock macOS + git (all scripts are Bash)
- **1500+ lines** of audited shell with shellcheck-clean CI
- **32 security checks** covering Core Security, Network, Auth, Persistence, Privacy, and Additional

---

## Table of Contents

- [Quick Start](#quick-start)
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

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
rcc audit
```

Clones to `~/.raccoon`, symlinks `rcc` to `/usr/local/bin`. Run `rcc` for the interactive menu or `rcc <command>` for direct access.

<img src="docs/gifs/rcc-help.gif" alt="rcc help output" width="600">

---

## Usage & Examples

```
rcc [command] [options]
```

Run `rcc` with no arguments → interactive menu. Pass a command for direct access.

<img src="docs/gifs/rcc-menu.gif" alt="rcc interactive menu" width="600">

**Quick checks:**

```bash
rcc audit            # 32-point security scan
rcc disk             # APFS volumes, SMART status, free space
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

<img src="docs/gifs/rcc-audit.gif" alt="rcc audit" width="600">
<img src="docs/gifs/rcc-battery.gif" alt="rcc battery" width="600">

---

## Commands

| Command | Description |
|---------|-------------|
| **Core Tools** | |
| `upgrade` | Update Homebrew, pip, npm, gem |
| `upgrade --dry-run` | Show what would be upgraded without updating |
| `audit` | Security audit (30+ checks) |
| `audit deep` | Full audit (requires sudo) |
| `audit fix` | Auto-fix common security issues |
| `audit json` | Audit output in JSON format |
| `audit history` | Audit history with diff |
| `audit watch` | Schedule weekly audit via LaunchAgent |
| **System** | |
| `network` | Interfaces, Wi-Fi, DNS, routing |
| `disk` | Disk space, APFS container, SMART |
| `memory` | Processes sorted by RAM |
| `ports` | Open ports and listening services |
| `battery` | Battery health, cycles, temperature |
| `backup` | Time Machine status |
| **Developer** | |
| `ssh` | SSH key generation and management |
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
│ Raccoon                                      │
│ macOS companion toolkit                      │
│                                              │
│ upgrade    audit      network    disk        │
│ memory     ssh        git        ports       │
│ battery    backup     env        startup     │
│ trash      fonts      history    certs       │
│ docker     xcode                             │
│                                              │
│ ←→ Navigate · ↑↓ Rows · Enter Run · Q Quit  │
└──────────────────────────────────────────────┘
```

Build it:

```bash
cd ui && ./build.sh
```

The binary is compiled to `bin/rcc-ui` and auto-detected by the `rcc` entrypoint.

---

## Security Audit

| Flag | Description |
|------|-------------|
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

History is saved to `~/.raccoon/audit-history/`; last 30 runs are kept automatically.

---

## Shell Completion

Install completion for the current shell:

```bash
# Bash
source <(rcc completion bash)

# Zsh
source <(rcc completion zsh)
```

To make it permanent:

```bash
# Bash — add to ~/.bashrc
source <(rcc completion bash)

# Zsh — add to ~/.zshrc
source <(rcc completion zsh)
```

Completions cover all commands, flags, and audit subcommands (`deep`, `fix`, `json`, `history`, etc.).

---

## Man Page

```bash
man rcc
```

Covers all commands, flags, and examples. Installer symlinks it into `/usr/local/share/man/man1/rcc.1`. To read without installing:

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
# Install bats-core if needed
brew install bats-core

# Full suite
bats tests/

# Single file
bats tests/test_audit.bats
```

**Style:** All shell scripts pass `shellcheck`. Run before pushing:

```bash
shellcheck rcc install.sh bin/*.sh lib/core/*.sh
```

---

## Updating

Re-run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Or manually:

```bash
cd ~/.raccoon && git pull
```

---

## Uninstall

```bash
rm -rf ~/.raccoon
rm "$(which rcc)"
```

---

## Project Structure

```
Raccoon/
├── rcc                 # Entry point + dispatcher
├── install.sh          # One-line installer
├── LICENSE
├── .editorconfig
├── .github/
│   ├── workflows/      # CI: shellcheck + Go build + bats
│   ├── dependabot.yml
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
├── man/man1/
│   └── rcc.1           # Man page
├── ui/                 # Go Bubble Tea TUI
│   ├── main.go
│   ├── go.mod
│   └── build.sh
├── bin/                # Diagnostic scripts
│   ├── audit.sh        # 896-line security audit engine
│   ├── network.sh
│   ├── disk.sh
│   ├── memory.sh
│   ├── ports.sh
│   ├── battery.sh
│   ├── backup.sh
│   ├── ssh.sh
│   ├── git.sh
│   ├── docker.sh
│   ├── xcode.sh
│   ├── env.sh
│   ├── startup.sh
│   ├── trash.sh
│   ├── fonts.sh
│   ├── history.sh
│   ├── certs.sh
│   └── upgrade.sh      # Multi-package upgrade tracker
├── lib/core/           # Shared library
│   ├── common.sh
│   └── commands.sh
├── completions/        # Shell autocompletion
│   ├── bash/
│   │   └── rcc.bash
│   └── zsh/
│       └── _rcc
└── tests/              # Bats test suite
    ├── test_helper.bash
    ├── test_install.bats
    ├── test_commands.bats
    └── test_audit.bats  # 18 tests for audit engine
```

---

## License

MIT — see [LICENSE](LICENSE).
