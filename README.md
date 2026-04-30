# 🦝 Raccoon

> A macOS companion toolkit for power users.

Raccoon (`rcc`) is a lightweight Bash toolkit for macOS that surfaces the information and workflows you need most — network state, hardware health, package hygiene, SSH, Git — through a single unified CLI with an interactive TUI featuring real-time progress bars and command search.

**Version:** 0.3.0

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Raccoon clones itself to `~/.raccoon` and symlinks `rcc` into `/usr/local/bin` (or `~/.local/bin` if `/usr/local/bin` is not writable).

### Requirements

- macOS 11+ (Big Sur or later)
- `git` (for installation)
- Go 1.21+ (only if you want to modify and recompile the UI manually)

The installer handles Go compilation automatically — no manual build step required.

---

## Usage

```
rcc [command] [options]
```

Run `rcc` with no arguments to open the interactive menu.

### Interactive UI

Raccoon includes an interactive menu built with Go and Bubble Tea. It launches automatically when you run `rcc` with no arguments. If Go is not available, it falls back to a bash-based menu with the same search functionality.

**Features:**
- **Search**: Press `/` to filter commands by name or description (case-insensitive)
- **Dynamic Grid**: Columns adapt automatically based on the number of results
- **Persistent Output**: After running a command, the output remains visible and the menu reappears below it
- **Keyboard Navigation**: Use arrow keys or `h/j/k/l` to navigate, `Enter` to run, `q` to quit

<!-- screenshot coming soon -->
![Raccoon Interactive Menu](docs/screenshot.png)

### Commands

| Command | Description |
|---------|-------------|
| **Core Tools** | |
| `upgrade` | Update Homebrew, pip, npm, gem, and other package managers |
| `upgrade --dry-run` | Show what would be upgraded without updating |
| `audit` | Security audit (30 checks: Core, Network, Auth, Persistence, Additional) |
| `audit deep` | Full audit (+ Privacy checks: Location Services, Analytics) |
| `audit quiet` | Audit output just counts: "pass warn fail" |
| `audit fix` | Auto-fix common security issues |
| `audit json` | Audit output in JSON format |
| `audit history` | Show audit history with diff |
| `audit watch` | Schedule weekly audit via LaunchAgent |
| **System** | |
| `network` | Network interfaces, Wi-Fi signal, DNS, routing |
| `disk` | Disk space, APFS container, SMART status |
| `memory` | Processes sorted by memory usage |
| `ports` | Open ports and listening services |
| `battery` | Battery health, cycle count, temperature |
| `backup` | Time Machine status and last backup date |
| **Developer** | |
| `ssh` | SSH key generation and management |
| `git` | Git status, branches, stash, and cleanup |
| `docker` | Docker images, containers, volumes |
| `xcode` | Simulators, derived data, SPM packages |
| **Maintenance** | |
| `env` | Shell environment and PATH summary |
| `startup` | Launch agents and login items |
| `trash` | Trash contents and size |
| `fonts` | Font duplicates and corrupted fonts |
| `history` | Shell command history analysis |
| `certs` | SSL certificates and expiration |
| **Meta** | |
| `--version` / `-V` | Print Raccoon version |
| `help` / `--help` / `-h` | Show help |

### Audit Options

| Option | Description |
|--------|-------------|
| `--deep` | Run all 32 security checks (requires sudo) |
| `--quiet` | Output just "pass warn fail" counts |
| `--json` | Output in JSON format |
| `--csv` | Output in CSV format |
| `--html` | Output as HTML report |
| `--report FILE` | Save report to file |
| `--fix` | Auto-fix issues where possible |
| `--fix --dry-run` | Show what would be fixed |
| `--fix --force` | Skip confirmation prompts |
| `--history` | Show audit history with diff |
| `--diff` | Show changes since last audit |
| `--watch` | Schedule weekly audit run |
| `--notify` | Send notification on completion |

---

## Global Progress Bar

Commands with multi-step operations (`upgrade`, `audit`, `git`, `docker`) display a single global progress bar fixed at the top of the terminal:

- **Real-time info**: The bar shows live status parsed from command output (e.g., "brew: upgrade deno", "audit: FileVault...")
- **Scrolling output**: Command output scrolls cleanly below the progress bar
- **Final summary**: After completion, formatted results appear (tables, ASCII boxes, etc.)

Example:
```
[██████████░░] 2/6 managers
brew: upgrade deno
------------------------------
==> Downloading deno... 60%
```

---

## Update

The installer handles updates automatically — just re-run the install command:

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Or, if you prefer updating manually:

```bash
cd ~/.raccoon && git pull
```

---

## Uninstall

```bash
rm -rf ~/.raccoon
rm /usr/local/bin/rcc   # or ~/.local/bin/rcc
```

---

## What Raccoon does

Raccoon focuses on system monitoring, diagnostics, and maintenance through an interactive TUI with real-time progress bars and command search — not cleanup or optimization. It provides actionable insights into your Mac's health, network, security, and performance.

---

## Structure

```
Raccoon/
├── rcc              # Entry point and command dispatcher
├── install.sh       # One-line installer
├── bin/             # Individual command scripts
│   ├── upgrade.sh
│   ├── audit.sh
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
│   └── menu.sh      # Interactive grid menu (bash fallback)
├── lib/
│   └── core/
│       ├── common.sh    # Shared utilities and banner
│       └── commands.sh  # Version, help, menu
└── ui/
    ├── main.go          # Go UI with Bubble Tea
    ├── go.mod           # Go module
    └── build.sh         # UI build script
```

---

## License

MIT
