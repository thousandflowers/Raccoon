# Raccoon

```
     _
   / \_/\_   Raccoon
  ( o.o )   Mac companion toolkit. Beyond Mole's scope.
   > ^ <
```

[![shell-bash](https://img.shields.io/badge/shell-bash-blue)](https://www.gnu.org/software/bash/)
[![macOS-compatible](https://img.shields.io/badge/macOS-compatible-brightgreen)](https://www.apple.com/macos/)
[![license-MIT](https://img.shields.io/badge/license-MIT-lightgrey)](https://opensource.org/licenses/MIT)
[![version-0.1.0](https://img.shields.io/badge/version-0.1.0-purple)](https://github.com/thousandflowers/Raccoon/releases)

## Why Raccoon

Raccoon is a companion to [Mole](https://github.com/tw93/Mole). While Mole focuses on cleanup and disk optimization, Raccoon covers the features Mole intentionally leaves out: package manager updates, network inspection, battery diagnostics, and backup monitoring.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Homebrew tap (coming soon):

```bash
brew tap thousandflowers/raccoon
```

## Commands

### rcc ssh

```bash
━━ SSH Keys & Config

[1/4] Unprotected keys... ✓
[2/4] Orphan keys... ✓
[3/4] Key permissions... ✓
[4/4] SSH config... ✓
✓ Completed: 4/4 passed
```

Checks SSH keys for:
- Unprotected keys (no passphrase)
- Orphan keys (private key without .pub)
- Key permissions (should be 600)
- SSH config (PasswordAuthentication, Host count)

### rcc git

```bash
━━ Git Repository Check

[1/2] Scanning repos... ✓
[2/2] Checking status...
  ~/Projects/myrepo
    ○ 3 uncommitted changes
    ○ 2 unpushed commits
    ○ 1 stash
✓ Completed: 2/2 passed
```

Scans for git repos in ~, ~/Desktop, ~/Documents, ~/Developer, ~/Projects, ~/dev, ~/code, ~/github and checks for uncommitted changes, unpushed commits, stashes, and detached HEAD.

### rcc upgrade [--dry-run]

```bash
━━ Upgrade Package Managers
[████████░░] 3/4  Upgrading nvm...
✓ Completed: 4/4 passed
```

### rcc ports

```bash
━━ Network Ports
  PORT     PROTO  PROCESS              STATE
  ────────────────────────────────────────────
  7000     TCP    ControlCenter        LISTEN
  52177    TCP    rapportd             ESTABLISHED
  5000     TCP    ControlCenter        LISTEN
```

### rcc battery

```bash
━━ Battery Status

Battery Health
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Cycle Count:    571
  Max Capacity:   85% (good)
  Condition:      Normal

Charge Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Charge Level:   100%
  Charging:       No
```

### rcc backup

```bash
━━ Time Machine Backup

[1/2] Checking status... ✓
  Destination:  My Backup Drive
  Last Backup:  2026-04-27 (2h ago)
✓ Completed: 2/2 passed
```

### rcc env

```bash
━━ Environment Check

[1/4] PATH entries... ✓
[2/4] Broken symlinks... ✓
[3/4] Duplicates... ✓
[4/4] Tool versions... ✓
✓ Completed: 4/4 passed
```

Checks:
- PATH entries (valid directories)
- Broken symlinks in PATH
- Duplicate PATH entries
- Tool versions (git, curl, wget, python3, node, brew, docker)

## Pairs well with

[Mole](https://github.com/tw93/Mole) - Deep clean and optimize your Mac

---

MIT License