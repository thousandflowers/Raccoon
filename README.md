# Raccoon

<div align="center">

```
     _
   / \_/\_   Raccoon
  ( o.o )   Mac companion toolkit. Beyond Mole's scope.
   > ^ <
```

**Professional system administration for power users**

[Install](#install) · [Commands](#commands) · [Audit](#security-audit) · [Menu](#interactive-menu)

</div>

---

## Why Raccoon?

Raccoon is a professional-grade macOS companion toolkit designed for developers and power users who need comprehensive system diagnostics, security auditing, and maintenance tools — all from a single CLI.

- **32 security checks** with `rcc audit --deep`
- **One-command system audits** with pass/warn/fail scoring
- **Interactive menu** with keyboard navigation
- **Zero dependencies** — pure bash

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/thousandflowers/Raccoon.git ~/.raccoon
echo 'export PATH="$HOME/.raccoon:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## Quick Start

```bash
rcc upgrade          # Update all package managers (Homebrew, pip, npm, etc.)
rcc audit           # Quick security check (6 scans)
rcc audit deep     # Full security audit (32 scans)
rcc network        # Network interfaces, DNS, open ports
rcc disk           # Disk space & SMART status
```

---

## Commands

### Security

| Command | Description |
|---------|-------------|
| `rcc audit` | Quick security scan (6 checks) |
| `rcc audit deep` | Full security audit (32 checks with sudo) |
| `rcc audit quiet` | Quiet mode (summary only) |
| `rcc audit fix` | Auto-fix security issues |
| `rcc audit json` | JSON output for scripting |
| `rcc audit history` | View previous audit runs |
| `rcc audit watch` | Schedule weekly auto-audit |

### System

| Command | Description |
|---------|-------------|
| `rcc battery` | Battery health & cycle count |
| `rcc backup` | Time Machine status |
| `rcc memory` | Processes by memory usage |
| `rcc disk` | Disk space & SMART status |

### Network

| Command | Description |
|---------|-------------|
| `rcc network` | Interfaces, DNS, latency |
| `rcc ports` | Open ports & listeners |

### Development

| Command | Description |
|---------|-------------|
| `rcc git` | Local repository status |
| `rcc ssh` | SSH keys & config |
| `rcc xcode` | Simulators & derived data |
| `rcc docker` | Images & containers |
| `rcc upgrade` | Update package managers |

### Utilities

| Command | Description |
|---------|-------------|
| `rcc env` | PATH, symlinks, tool versions |
| `rcc fonts` | Font duplicates |
| `rcc history` | Shell command history |
| `rcc certs` | SSL certificates |
| `rcc trash` | Trash contents |
| `rcc startup` | Launch agents & login items |

---

## Security Audit

### Quick Scan (6 checks)

```bash
$ rcc audit

━━ Security Audit

[Persistence]
✓ User LaunchAgents: 5 items
✓ System LaunchAgents: 6 items
✓ LaunchDaemons: 13 items
✓ Cron Jobs: None
✓ At Jobs: None
✓ Login Items: 10 items

━━ Summary
  Pass:    6
  Warning: 0
  Fail:    0

✓ All checks passed
✓ Completed
```

### Deep Scan (32 checks)

```bash
$ rcc audit deep

━━ Security Audit (DEEP MODE)

[Core Security]
⚠ FileVault: Unknown
✓ SIP: Enabled
✓ Gatekeeper: Enabled
✓ Firewall: Enabled
⚠ Stealth Mode: Disabled
✓ Software Updates: Up to date

[Network]
⚠ Open Ports: 37 listening
✓ DNS Servers: fd7a:115c:a1e0::53
✓ VPN: None configured
⚠ Bluetooth: Unknown
⚠ Sharing: 1 enabled
⚠ SSH Daemon: Running

[User & Auth]
✓ Auto-Login: Disabled
✓ Keychain: 2 available
✓ SSH Keys: None
✓ Authorized Keys: None
✓ Sudoers: OK

[Persistence]
✓ User LaunchAgents: 5 items
✓ System LaunchAgents: 6 items
✓ LaunchDaemons: 13 items
✓ Cron Jobs: None
✓ At Jobs: None
✓ Login Items: 10 items

[Privacy]
⚠ Location Services: Unknown
✓ Analytics: Disabled

[Additional]
⚠ XProtect: Unknown
⚠ Screen Lock: Default
⚠ .ssh Permissions: Insecure
⚠ Quarantined Files: 782
✓ Kernel Extensions: 1 (third-party)
✓ Sudo Access: Available
⚠ DNS-over-HTTPS: Disabled

━━ Summary
  Pass:    20
  Warning: 12
  Fail:    0

⚐ No critical issues
✓ Completed
```

### Audit Options

```bash
rcc audit --quiet          # Summary only: "20 12 0"
rcc audit --fix           # Prompt to fix issues
rcc audit --fix --dry-run # Show fixes without applying
rcc audit --fix --force   # Apply fixes without prompt
rcc audit --json          # JSON output
rcc audit --csv          # CSV output
rcc audit --html          # HTML report
rcc audit --report file   # Save to file
```

---

## Interactive Menu

Launch with `rcc` (no arguments):

```bash
$ rcc

     _
   / \_/\_   Raccoon
  ( o.o )   Mac companion toolkit. Beyond Mole's scope.
   > ^ <

▶ 1. upgrade:Update packages
  2. audit:Security audit (quick)
  3. audit deep:Security audit (full)
  4. network:Network info
  5. disk:Disk space
  6. memory:Memory usage
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  7. audit quiet:audit --quiet
  8. audit fix:audit --fix
  9. audit json:audit --json
 10. audit history:audit --history
 11. audit watch:audit --watch
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 12. ssh:SSH keys
 13. git:Git repos
 14. ports:Open ports
 15. battery:Battery health
 16. backup:Time Machine
 17. env:Environment
 18. startup:Launch agents
 19. trash:Trash
 20. fonts:Fonts
 21. history:Shell history
 22. certs:SSL certificates
 23. docker:Docker
 24. xcode:Xcode

↑↓ Navigate | Enter | Q Quit
```

**Controls:**
- `↑↓` — Navigate
- `Enter` — Select
- `Q` — Quit

---

## Example Commands

### Battery

```bash
$ rcc battery

━━ Battery Status

Cycle Count:      571
Max Capacity:     85%
Condition:       Normal
Charge Level:    100%

✓ Completed
```

### Network

```bash
$ rcc network

━━ Network Status

[1/10] Interfaces
Name         Type            Value
────────────────────────────────────────────────────
lo0          (Loopback):     ::1
en0          (LAN):          192.168.1.191

[2/10] DNS Servers
Primary:     192.168.1.1

✓ Completed
```

---

## Requirements

- macOS 12+ (Monterey or later)
- Bash 3.2+ (ships with macOS)
- No dependencies — pure bash

---

## Pairs Well With

[Mole](https://github.com/tw93/Mole) — Deep clean and optimize your Mac

---

## License

MIT License — see [LICENSE](LICENSE)

---

<div align="center">

**Made with ❤️ for macOS power users**

</div>