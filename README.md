# 🦝 Raccoon

<p align="center">
  <img src="docs/gifs/hero.gif" alt="Raccoon Hero" width="800">
</p>

> Security audits, system info, and SSH fleet management for macOS — for the people who maintain Macs they don't sit in front of, and need to show their work.

[![CI](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Go](https://img.shields.io/badge/Go_TUI-Bubble_Tea-00ADD8?logo=go)](ui/)
![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)
![Tests](https://img.shields.io/badge/tests-bats-blue)
[![Stars](https://img.shields.io/github/stars/thousandflowers/Raccoon?style=flat)](https://github.com/thousandflowers/Raccoon/stargazers)

Zero dependencies beyond macOS + git. 1500+ lines of shellcheck-clean Bash. 322 tests. Bash 3.2 compatible.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Or via Homebrew:

```bash
brew install thousandflowers/raccoon/rcc
```

Run `rcc` to launch the interactive menu, or `rcc <command>` for direct access.

<details>
<summary>Update & uninstall</summary>

**Update:**

```bash
# Homebrew
brew upgrade rcc

# curl install — re-run the installer
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

**Uninstall:**

```bash
# Homebrew
brew uninstall rcc

# curl install
rm -rf ~/.raccoon && rm "$(which rcc)"
```
</details>

---

## Why I built this

It started as a PR to [Mole](https://github.com/tw93/Mole) — a `mo update` command that updated brew, pip, npm, and gem in one shot, because I always forgot to update something. The maintainer liked the code but declined it as out of scope.

So I took it further. I had a second script I ran on my sisters' Macs whenever they asked me to check something — disk space, open ports, what was running at startup. I merged the two and kept adding commands. Now it produces client reports and audits a room full of Macs over SSH, but it's still the same tool — I just kept adding the things I needed.

---

## What you can do

### 🔒 Security audit

30+ checks across Core Security, Network, Auth, Persistence, Privacy, and more.

```bash
rcc audit                 # quick scan
rcc audit deep            # full scan (requires sudo)
rcc audit --fix           # auto-fix common issues
rcc audit --explain       # add plain-language notes to issues
rcc audit --remediation   # client-facing intervention report
rcc audit --json          # machine-readable output
rcc audit --csv           # spreadsheet-ready
rcc audit --html          # save as HTML report
rcc audit --md            # client-ready Markdown report
rcc audit --rtf           # client-ready RTF (opens in TextEdit/Word)
rcc audit --report out    # save report to file (format inferred from extension)
rcc audit history         # view past audits
rcc audit --diff          # changes since last audit
rcc audit watch           # schedule weekly scan via LaunchAgent
```

**Per-client profiles.** `--profile <name>` loads a client's config, branding, and
baseline. Combine it with `--remediation` and `--sheet` to produce a complete
intervention report in one command:

```bash
rcc audit --deep --profile mario-bianchi \
  --remediation --sheet --hours 2 \
  --report intervento.md
```

**Client-ready reports.** `--md` and `--rtf` produce a branded document a
technician can hand to a client. Add `--client`, `--shop`, and `--tech` for the
header/footer (all optional — without them you get a default Raccoon report):

```bash
rcc audit --md --report client.md \
  --client "Jane Doe" --shop "MacFix Pro" --tech "Mario Rossi"
```

The reporter is data-driven: it renders whatever checks the audit produces, so
new checks show up automatically with no change to the report code.

**Safe by default.** `--fix` never imposes a one-size-fits-all setting — a config
that looks odd on one Mac is often legitimate on another:

- Destructive fixes (cron, SSH `authorized_keys`, LaunchAgents, login items)
  snapshot the originals to `~/.raccoon/fix-backups/<timestamp>/` before changing
  anything, so a wrong fix is recoverable.
- Raccoon never sets a public DNS resolver for you or strips the Gatekeeper
  quarantine flag — both would silently weaken a working setup.
- Opt a machine out of any fix: list its check names in `~/.raccoon/audit.conf`,
  one per line (`#` for comments). Those checks are reported but never auto-fixed.

```bash
# ~/.raccoon/audit.conf — never auto-fix these on this Mac
Cron Jobs
User LaunchAgents
```

### 🛰️ Fleet mode

Audit every Mac you manage from one command, over SSH, in parallel:

```bash
rcc fleet add mario@192.168.1.10   # build the host list
rcc fleet status                   # quick reachability check
rcc fleet audit                    # audit all hosts, aggregate report
rcc fleet audit --report fleet.md  # save an aggregate Markdown report
```

Hosts live in `~/.raccoon/fleet.conf` (one `user@host[:port]` per line, key auth
only). **Remote Macs don't need Raccoon installed** — the script is streamed over
stdin to `bash`, so they need only bash, macOS, and an SSH server. sudo checks
are skipped automatically (SSH BatchMode has no sudo).

### 🖥️ System information

```bash
rcc disk                  # internal, external & network drives, SMART
rcc disk large            # biggest files (--min SIZE, --top N)
rcc network               # interfaces, Wi‑Fi, DNS, routing
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
rcc upgrade               # update brew, pip, npm, gem at once
rcc upgrade --dry-run     # preview upgrades without running them
rcc apps                  # update GUI apps (App Store + Homebrew casks)
rcc apps --dry-run        # preview app updates without running them
rcc ssh                   # inspect keys, --export, --export-gpg
rcc git                   # status, branches, stash, cleanup
rcc docker                # images, containers, volumes
rcc xcode                 # simulators, derived data, SPM caches
```

<details>
<summary>📸 Command demos</summary>

**Security**

![audit](docs/gifs/rcc-audit.gif)

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

| Command | Description |
|---------|-------------|
| `apps` | Update GUI apps (App Store + casks) |
| `audit` | Security audit (30+ checks) |
| `audit deep` | Full audit with sudo |
| `audit fix` | Auto-fix security issues |
| `audit --explain` | Audit with plain-language notes on issues |
| `audit --remediation` | Client-facing before/after intervention report |
| `audit --baseline` | Save a reference baseline; `--baseline-diff` shows regressions since |
| `audit --schedule FREQ` | Schedule a deep audit (daily/weekly/monthly); `status`/`remove` |
| `audit profile` | Per-client profiles (config, branding, baseline); `profile-list` |
| `audit share` | Publish the report as an anonymous GitHub Gist |
| `audit --sheet` | Intervention sheet (`--hours`, `--notes`); MD or RTF |
| `battery` | Health, cycles, temperature |
| `backup` | Time Machine status |
| `certs` | SSL certificate expiry |
| `disk` | Internal, external & network drives, SMART |
| `disk large` | Biggest files (`--min SIZE`, `--top N`) |
| `docker` | Images, containers, volumes |
| `env` | Shell environment & PATH |
| `fonts` | Font duplicates & issues |
| `git` | Status, branches, stash |
| `history` | Shell history analysis |
| `memory` | System memory + process RSS |
| `network` | Interfaces, Wi‑Fi, DNS |
| `wifi` | Active network, known SSIDs, Keychain passwords |
| `fleet` | Security audit across multiple Macs via SSH |
| `ports` | Open ports & listeners |
| `ssh` | Key inspection, `--export`, `--export-gpg` |
| `startup` | Launch agents & login items |
| `startup clean` | Remove orphaned launch agents (interactive, with backup) |
| `trash` | Trash contents & size |
| `upgrade` | Multi‑package update |
| `xcode` | Simulators, caches, SPM |

---

## Why Raccoon is different

**Safe by default, not silent by default.** `--fix` backs up every destructive
change to `~/.raccoon/fix-backups/<timestamp>/` before touching anything. A wrong
fix is always recoverable.

**No install on the remote Macs.** Fleet mode streams the audit script over SSH
stdin — remote machines need only bash, macOS, and an open SSH server.

**Auditable, not opinionated.** Raccoon never sets a public DNS resolver or strips
Gatekeeper quarantine flags. Both would silently weaken a working setup on some
machines.

**One data model.** Every output format — text, JSON, CSV, Markdown, RTF, and the
fleet aggregate — renders from the same `AUDIT_RESULTS` array, so a new check shows
up everywhere automatically.

**Bash 3.2 compatible.** Runs on any macOS since Snow Leopard. No Homebrew required
to install, no runtime dependencies.

**322 tests.** Every renderer, flag, and edge case (including pre-feature history
files) has a bats test, and `shellcheck -S warning` exits 0 on every file.

---

## Go TUI

Raccoon ships an optional terminal UI built with [Bubble Tea](https://github.com/charmbracelet/bubbletea):

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
│ ←→ Navigate · ↑↓ Rows · Enter Run · Q Quit   │
└──────────────────────────────────────────────┘
```

Compile with `cd ui && ./build.sh`. The binary lands in `bin/rcc-ui` and is auto-detected by `rcc`.

---

## Shell completion

```bash
rcc completion bash    # print bash completions
rcc completion zsh     # print zsh completions
```

Pipe into your shell rc file to make it permanent:

```bash
rcc completion bash >> ~/.bashrc
rcc completion zsh  >> ~/.zshrc
```

---

## Man page

```bash
man rcc
```

Covers every command, flag, and example.

---

## Project structure

```
Raccoon/
├── rcc                  # Entry point + dispatcher
├── install.sh           # curl | bash installer
├── lib/core/            # Shared shell library
│   ├── common.sh
│   └── commands.sh
├── bin/                 # Command scripts (audit, disk, …)
├── ui/                  # Go Bubble Tea TUI
├── completions/         # bash + zsh autocompletions
├── man/man1/rcc.1      # Man page
├── tests/               # Bats test suite
└── docs/                # Images, GIFs, guides
```

---

## Contributing

Bug reports and PRs welcome — use the templates.

```bash
brew install bats-core shellcheck
bats tests/              # run tests
shellcheck rcc bin/*.sh lib/core/*.sh   # lint
```

---

## License

MIT — see [LICENSE](LICENSE).
