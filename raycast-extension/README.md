# Raccoon

Run [Raccoon](https://github.com/thousandflowers/Raccoon) — a macOS companion toolkit — from Raycast.

Raccoon reports on disk, memory, open ports, battery, network, Wi-Fi, SSH keys, certificates,
launch agents, fonts, Docker and Xcode, and can run a security audit of the machine.

## Setup

This extension drives the `rcc` command-line tool. Install it once:

```sh
brew install thousandflowers/raccoon/rcc
```

If `rcc` lives somewhere unusual, set its full path in the extension preferences.

## Commands

| Command | What it does |
| ------- | ------------ |
| Search Raccoon Commands | Browse and run every `rcc` subcommand |
| Show Disk Space | Disks, volumes and the largest space hogs |
| Show Memory Usage | Memory pressure and the hungriest processes |
| List Open Ports | Open TCP/UDP ports with the owning process |
| Show Battery Health | Cycle count, max capacity, charging status |
| Run Security Audit | Full security audit, with a confirmed one-press fix |
| Configure Admin Session | Ask for Touch ID once instead of once per privileged command |

Everything runs inside Raycast; no Terminal window is ever opened. Output streams into the
view as it arrives, so long commands (`upgrade`, `audit --deep`) show progress and can be
stopped.

## Administrator rights

`audit`, `upgrade`, `apps` and `fleet` need root; the other 24 commands never ask for anything.

macOS ties a sudo authentication to the process tree when there is no controlling terminal, and
Raycast starts a fresh process for every command. So out of the box each privileged run asks for
Touch ID again - no extension code can share that ticket.

**Configure Admin Session** fixes it by installing a small sudoers drop-in that keys the record
to your user instead:

```
/etc/sudoers.d/raccoon

Defaults:<you> timestamp_type=global
Defaults:<you> timestamp_timeout=60
```

The duration is an extension preference: **Expires after 60 minutes** (default) or **Until
restart**. The file is checked with `visudo -c` before installation, and only the final copy runs
as root, so a malformed drop-in can never reach `/etc/sudoers.d`.

This relaxes sudo for every process you own, not only Raccoon, for that duration. Undo it from
the same command, or with `sudo rm /etc/sudoers.d/raccoon`.
