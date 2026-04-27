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

Time Machine Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Destination:  My Backup Drive
  Last Backup:  2026-04-27 (2h ago)
```

## Pairs well with

[Mole](https://github.com/tw93/Mole) - Deep clean and optimize your Mac

---

MIT License