# 🦝 Raccoon

**macOS companion toolkit — security audit + developer health.**

[![CI](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Raccoon/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)]()
[![Zero Deps](https://img.shields.io/badge/deps-0-darkgreen)]()
[![Go TUI](https://img.shields.io/badge/Go_TUI-Bubble_Tea-00ADD8?logo=go)](ui/)

```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
rcc audit
```

Una CLI. Zero dipendenze oltre macOS e git. **32 controlli di sicurezza** + diagnostica per sviluppatori.

---

## Perché Raccoon

Altri strumenti di audit esistono, ma nessuno include strumenti per chi sviluppa:

| | Raccoon | Mergen | mac_audit |
|---|---|---|---|
| Security audit (32 check) | ✅ | ✅ | ✅ |
| Git status, stash, cleanup | ✅ | ❌ | ❌ |
| Docker images, containers | ✅ | ❌ | ❌ |
| Xcode simulatori, SPM | ✅ | ❌ | ❌ |
| SSH key management | ✅ | ❌ | ❌ |
| Multi-package upgrade tracker | ✅ | ❌ | ❌ |
| TUI interattivo | ✅ | ✅ | ❌ |
| Zero runtime deps (Bash + Go) | ✅ | Go only | Python |

Raccoon non è solo un audit. È il toolbox per sviluppatori macOS.

---

## Comandi

```bash
rcc audit            # 32-point security scan
rcc audit --deep     # Full scan (sudo)
rcc audit --fix      # Auto-ripara
rcc audit --json     # Output JSON
rcc disk             # APFS, SMART, spazio
rcc network          # Wi-Fi, DNS, routing
rcc battery          # Salute, cicli, temperatura
rcc upgrade          # Brew + pip + npm + gem
rcc git              # Status, branch, cleanup
rcc docker           # Immagini, container, volumi
rcc xcode            # Simulatori, derived data
rcc ssh              # Chiavi SSH
rcc memory           # Processi per RAM
rcc ports            # Porte aperte
```

Tutti i flag in due forme: `rcc audit deep` o `rcc audit --deep`.

---

## Output

```bash
$ rcc audit
═══ Raccoon Security Audit ═══

 ✓ Gatekeeper enabled
 ✓ SIP enabled
 ✓ FileVault enabled
 ✓ Firewall enabled
 ✗ Remote login enabled
 ...

 Result: 24 pass · 5 warn · 2 fail · 31 total
```

---

## TUI

Con [Bubble Tea](https://github.com/charmbracelet/bubbletea):

```bash
cd ui && ./build.sh
```

```
┌──────────────────────────────────────────────┐
│ Raccoon                                      │
│ upgrade    audit      network    disk        │
│ memory     ssh        git        ports       │
│ battery    backup     env        startup     │
│ docker     xcode                             │
└──────────────────────────────────────────────┘
```

---

## Install

```bash
# One-liner
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash

# Manual
git clone https://github.com/thousandflowers/Raccoon ~/.raccoon
ln -s ~/.raccoon/rcc /usr/local/bin/rcc
```

---

## Progetti correlati

- [**Parrot**](https://github.com/thousandflowers/Parrot) — correzione grammaticale offline macOS
- [**qr-multi-imgs**](https://github.com/thousandflowers/qr-multi-imgs) — scanner QR batch Go TUI
- [**Stockfish Continue to Play**](https://github.com/thousandflowers/stockfish-continue-to-play) — estensione Chrome scacchi

---

## License

MIT — [LICENSE](LICENSE).
