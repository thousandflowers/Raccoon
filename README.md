# 🦝 Raccoon

[![Version](https://img.shields.io/badge/version-0.5.0-blue.svg)](https://github.com/thousandflowers/Raccoon)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-11%2B-blueviolet.svg)](https://www.apple.com/macos/)

> **The macOS companion toolkit with an animated raccoon TUI.**

Per-script ASCII animations. Real-time progress bar with percentage.  
18 commands for health, network, security, packages — all in one place.

---

## 🎬 See it in action

```
  Raccoon running upgrade              installed ✓
       _                               ( ^.^ )
     / \_/\_                             ╲_/\_/
    ( o.o )─[ ]  upgrade              —————————————————
     > ^ <                              ✓ Completed
  —————————————————
  ██████░░ 5/18 (27%)  brew: upgrading...
  ───────────────── upgrade ────
  │ ==> Updating Homebrew...
  │ Already up-to-date.

  Running · press q to quit
```

**Every script has its own raccoon animation** — trash panda, detective, sysadmin, docker stacker, and more.

---

## 🚀 Install in 10 seconds

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

That's it. `rcc` is now in your PATH.

### Requirements

- macOS 11+ (Big Sur or later)
- `git` (for installation)
- Go 1.21+ (only if you want to modify and recompile the UI manually)

The installer handles Go compilation automatically — no manual build step required.

---

## ✨ Why Raccoon?

| ⚡ Fast | 🔍 Searchable | 🦝 Animated |
|:------:|:-----------:|:----------:|
| One command gets you everything. | Press `/` to filter 18+ commands instantly. | Each command has a unique raccoon animation. |
| No config files to manage. | Case-insensitive, searches name + description. | Trash panda digs, detective inspects, sysadmin builds. |
| Runs on stock macOS tools. | Menu reappears after execution. | Raccoon body moves: ears perk, arms reach, posture shifts. |

---

## 📊 Real-Time Progress

```
» upgrade                              ← title on its own line
   __\_/\_
  ( -.- )─[ ]                          ← 4-line ASCII art per script
   > ^ <
  ─────────────────────────
  ██████░░░ 5/18 (27%)  brew: upgrade  ← percentage + label
                                       ← padding zone
  ───────────────── upgrade ────       ← output separator
  │ ==> Updating Homebrew...           ← muted output
  │ Already up-to-date.

  Running · press q to quit
```

- **Granular progress** — 18 steps across 3 managers each reporting 3×
- **Live percentage** — bar shows `5/18 (27%)` updating in real time
- **Blank-line padding** keeps the bar zone visually separate from output
- **Muted `│` output** reduces visual noise below the progress area

---

## 🎮 Interactive Menu

**Launch:** `rcc` with no arguments  
**Search:** Press `/` then type (e.g., `up` → `upgrade`)  
**Navigate:** Arrow keys or `h/j/k/l`  
**Run:** `Enter`  
**Quit:** `q`

**Per-script raccoon animations** — each of the 18 commands has 8 hand-crafted frames with unique body shapes, objects, and action sequences:

| Script | Raccoon Style | What you see |
|--------|--------------|--------------|
| `upgrade` | sysadmin | grabs packages `[ ]` → installs `[█]` → ✓ |
| `audit` | detective | magnifying glass `O─` scans → finds bug → ✓ |
| `network` | antenna | signal `▽` grows → full bars → ✓ |
| `disk` | disk doctor | disk `[=]` gets cleaned → `!>` → ✓ |
| `memory` | RAM tech | chips `##` multiply → done → ✓ |
| `ports` | cable wrangler | jacks `┤├` connect → link → ✓ |
| `ssh` | locksmith | key `>-σ` turns → auth → ✓ |
| `git` | branch weaver | branches `><` split → merge → ✓ |
| `docker` | container stacker | boxes `┌#┐` pile up → built → ✓ |
| `trash` | trash panda | sniffs → digs `~~` → finds treasure → ♪ |
| `startup` | sleepyhead | curled `(-.-)z` → wakes → stretches → ✓ |
| `xcode` | builder | build arrow `=>` accelerates → ✓ |
| `battery` | charger | power `══` fills up → full |
| `backup` | time traveler | capsule `(())` spins → ◐ → ✓ |
| `history` | archivist | scrolls `@@` pile → organize → ✓ |
| `certs` | shield bearer | shield `<~>` verifies → ✓ |
| `fonts` | typographer | letters `Aa` compare → ✓ |
| `env` | pathfinder | shell `$%` navigates maze → ✓ |

Each animation cycles at 300ms with 8 frames — ears tilt, body leans, arms reach, eyes change expression.

---

## 📚 Commands

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

## 🏗️ How it works

Raccoon is built with two layers:

- **Core (Bash)** — 18 command scripts in `bin/` plus shared utilities in `lib/core/`. Every command works standalone via `rcc <command>`.
- **TUI (Go + Bubble Tea)** — Interactive menu in `ui/` that launches when you run `rcc`. Compiles on install, falls back to a bash-based menu if Go is unavailable.

**Animation system** (`ui/main.go`): Each of the 18 scripts has a hand-crafted `raccoonAnimation` — 8 frames of 4-line ASCII art. The frames are cycled at 300ms by a `tea.Tick` command. The raccoon's body, ears, arms, and props change per frame to tell a mini-story for that command (e.g., trash panda sniffs → digs → finds treasure → sleeps).

**Progress bar** (`lib/core/common.sh`): Bash scripts emit `__RCC_PROGRESS__:current:total:label` markers. The Go TUI parses these to render a real-time progress bar with percentage (`5/18 (27%)`). Works with `upgrade`, `audit`, `git`, and `docker`.

**Bash 3.2 compat**: All `[[ cond ]] || return` guards were rewritten to `if ! [[ cond ]]; then return; fi` — macOS default bash doesn't suppress errexit with `||` after `[[ ]]` inside functions.

---

## 🔄 Update

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Or manually:

```bash
cd ~/.raccoon && git pull
```

---

## 🗑️ Uninstall

```bash
rm -rf ~/.raccoon
rm /usr/local/bin/rcc   # or ~/.local/bin/rcc
```

---

## 📜 License

MIT © [thousandflowers](https://github.com/thousandflowers)
