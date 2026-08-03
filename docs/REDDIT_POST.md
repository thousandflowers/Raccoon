# [Showcase] Raccoon: A lightweight, zero-dependency macOS companion toolkit (Security Audit, System Diags, Dev Workflows)

Hi everyone!

I've been working on **Raccoon** (`rcc`), a macOS companion toolkit designed for power users and developers who want to keep their system lean, secure, and up-to-date without heavy apps or background daemons.

It's almost entirely written in Bash (audited with ShellCheck) and has an optional Go/Bubble Tea TUI for those who like a bit of visual flair in the terminal.

### 🦝 Key Features:
*   **Security Audit**: 32-point security scan (FileVault, SIP, Firewall, Persistence, Privacy, etc.) with auto-fix capabilities.
*   **Dev Workflow**: Unified `upgrade` command for Homebrew, npm, pip, and gem with tracked metrics.
*   **System Diagnostics**: Quick access to battery health, disk SMART status, network routing, open ports, and memory usage.
*   **Zero Dependencies**: Uses stock macOS tools. No need to install Python/Ruby/Node just to run it.
*   **Extensible**: Modular script-based architecture.

### 🚀 Quick Start
```bash
curl -fsSL https://raw.githubusercontent.com/thousandflowers/Raccoon/main/install.sh | bash
rcc audit
```

### 📦 Repository
[https://github.com/thousandflowers/Raccoon](https://github.com/thousandflowers/Raccoon)

I'd love to hear your feedback or suggestions for new checks/tools!

**GIFs/Screenshots in the README!**
