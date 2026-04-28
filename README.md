# 🦝 Raccoon

> A Mac companion toolkit for power users. Where [Mole](https://github.com/tw93/Mole) stops, Raccoon starts.

Raccoon (`rcc`) is a lightweight Bash toolkit for macOS that surfaces the information and workflows you need most — network state, hardware health, package hygiene, SSH, Git — through a single unified CLI with an optional interactive menu.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Raccoon clones itself to `~/.raccoon` and symlinks `rcc` into `/usr/local/bin` (or `~/.local/bin` if `/usr/local/bin` is not writable). No external dependencies beyond standard macOS utilities and `git`.

---

## Usage

```
rcc [command] [options]
```

Run `rcc` with no arguments to open the interactive menu.

### Commands

| Command   | Description                                      |
|-----------|--------------------------------------------------|
| `upgrade` | Update Homebrew, pip, npm and other package managers |
| `ports`   | Show open ports and active listeners             |
| `battery` | Battery health, cycle count, and charge status   |
| `backup`  | Verify Time Machine status and last backup date  |
| `ssh`     | SSH key and config management helpers            |
| `git`     | Git workflow utilities and diagnostics           |
| `env`     | Display shell environment summary                |
| `audit`   | Security audit (quick scan)                    |
| `audit deep` | Full security audit (32 checks)            |
| `network` | Network interfaces, DNS, open ports          |
| `disk`    | Disk space and SMART status                   |
| `memory`  | Processes by memory usage                     |
| `startup` | Launch agents and login items                |
| `trash`   | Trash contents and size                      |
| `fonts`   | Font duplicates and corrupted                 |
| `history` | Shell command history                        |
| `certs`   | SSL certificates in keychain                 |
| `docker`  | Docker images and containers                  |
| `xcode`   | Xcode simulators and derived data             |
| `--version` / `-V` | Print Raccoon version               |
| `help` / `--help` / `-h` | Show help                      |

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

## Pairs well with

[**Mole**](https://github.com/tw93/Mole) — Deep clean and optimize your Mac. Raccoon is designed as a complement to Mole, not a replacement.

---

## Structure

```
Raccoon/
├── rcc              # Entry point and command dispatcher
├── install.sh       # One-line installer
├── bin/             # Individual command scripts
│   ├── upgrade.sh
│   ├── ports.sh
│   ├── battery.sh
│   ├── backup.sh
│   ├── ssh.sh
│   ├── git.sh
│   ├── env.sh
│   ├── audit.sh
│   ├── network.sh
│   ├── disk.sh
│   ├── memory.sh
│   ├── startup.sh
│   ├── trash.sh
│   ├── fonts.sh
│   ├── history.sh
│   ├── certs.sh
│   ├── docker.sh
│   └── xcode.sh
└── lib/
    └── core/
        ├── common.sh    # Shared utilities and banner
        └── commands.sh  # Version, help, menu
```

---

## License

MIT
