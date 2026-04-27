# Raccoon

```
     _
   / \_/\_   Raccoon
  ( o.o )   Mac companion toolkit. Beyond Mole's scope.
   > ^ <
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

## Commands

### rcc battery

```bash
$ rcc battery

━━ Battery Status

[1/2] Fetch battery info... ✓
[2/2] Display status...
━━ Battery Health

  Cycle Count:      571
  Max Capacity:     85% (good)
  Condition:        Normal

━━ Charge Status

  Charge Level:     100%
  Charging:         No
  Fully Charged:    No

✓ Completed: 2/2 passed
```

### rcc ports

```bash
$ rcc ports

━━ Network Ports

  PORT     PROTO  PROCESS              STATE
  ────────────────────────────────────────────
  7000     TCP    ControlCenter        LISTEN
  5000     TCP    ControlCenter        LISTEN
  52177    TCP    rapportd             LISTEN
  50592    TCP    rapportd             LISTEN
  50593    TCP    rapportd             LISTEN
  3722     UDP    rapportd
```

### rcc backup

```bash
$ rcc backup

━━ Time Machine Backup

[1/2] Check TM destination... ✓
[2/2] Check last backup... ✓
  Destination:  TimeMachineDrive
  Last Backup:  2026-04-27 (3h ago)

✓ Completed: 2/2 passed
```

### rcc ssh

```bash
$ rcc ssh

━━ SSH Keys & Config

[1/5] Unprotected keys... ✓
[2/5] Orphan keys... ✓
[3/5] Directory permissions... ✓
[4/5] Key permissions... ✓
[5/5] SSH config... ✓
  Config file exists (3 host entries)

✓ Completed: 5/5 passed
```

### rcc git

```bash
$ rcc git

━━ Git Repository Check

[1/2] Scanning repos... ✓
[2/2] Checking status...
  ~/Projects/webapp
    ○ 12 uncommitted changes
    ○ 3 unpushed commits
    ○ 2 branches without upstream

  ~/Projects/api-server
    ○ 1 uncommitted changes

  ~/Developer/old-project
    ○ detached HEAD
    ○ 5 stashed changes

✓ Completed: 2/2 passed
```

### rcc upgrade

```bash
$ rcc upgrade

━━ Upgrade Package Managers

[1/6] Homebrew... ✓
[2/6] pip... ✓
[3/6] npm... ✓
[4/6] nvm... ✓
[5/6] rustup... ✓
[6/6] gem... ✓

✓ Completed: 6/6 passed
```

Dry-run mode:

```bash
$ rcc upgrade --dry-run

━━ Upgrade Package Managers

→ DRY RUN MODE, no packages will be updated

[1/6] Homebrew...
    postgresql    16.5.0 -> 16.6.0
    redis         7.2.3 -> 7.4.0
    python@3.12   3.12.6 -> 3.12.7
✓
[2/6] pip...
    requests    2.31.0 -> 2.32.0
    numpy       1.26.4 -> 1.27.0
✓
...
```

### rcc env

```bash
$ rcc env

━━ Environment Check

[1/4] PATH entries... ✓
  Total: 21 entries, 2 missing

[2/4] Broken symlinks... ✓
  ✗ /usr/local/bin/old-tool -> /removed/path

[3/4] Duplicates... ✓
  No duplicates found

[4/4] Tool versions... ✓
  git      2.50.1 (Apple Git-155)
  curl     8.7.1
  node     v22.12.0
  brew     4.3.0

✓ Completed: 4/4 passed
```

### rcc menu

Interactive menu with keyboard navigation:

```bash
$ rcc

     _
   / \_/\_   Raccoon
  ( o.o )   Mac companion toolkit. Beyond Mole's scope.
   > ^ <

→  1. ssh       Check SSH keys/config
   2. git       Check local git repos
   3. upgrade   Update package managers
   4. ports     Show open ports/listeners
   5. battery   Battery health & cycle count
   6. backup    Verify Time Machine status
   7. env       Check environment

  ↑↓  |  Enter  |  Q Quit
```

## Pairs well with

[Mole](https://github.com/tw93/Mole) - Deep clean and optimize your Mac

---

MIT License