#!/bin/bash
# preflight.sh: refuse to ship a capture that names the machine it came from.
#
# Reads a capture on stdin or as a file argument and prints every line that
# carries an identifier belonging to this machine. Exit 0 means clean.
#
#   ./docs/gif-helpers/preflight.sh docs/remotion/fixtures/disk.txt
#   HOME=$(mktemp -d) ./rcc disk | ./docs/gif-helpers/preflight.sh
#
# The identifiers are read at run time from whoami, hostname, ComputerName and
# $HOME rather than hard-coded, so this stays true on a machine that is not the
# one it was written on. The fixed patterns below catch the shapes that carry a
# machine identity even when the name itself is unknown.
set -uo pipefail

input="${1:--}"

# ponytail: an empty identifier would match every line, so each is dropped
# unless it is long enough to mean something.
patterns=()
add() { [[ ${#1} -ge 3 ]] && patterns+=("$1"); }

add "$(whoami 2>/dev/null)"
add "$(hostname 2>/dev/null)"
add "$(hostname -s 2>/dev/null)"
add "$(scutil --get ComputerName 2>/dev/null)"
add "$(scutil --get LocalHostName 2>/dev/null)"
[[ -n "${HOME:-}" ]] && add "$HOME" && add "$(basename "$HOME")"

# Shapes, not names: a home path other than the placeholder, a user@host pair,
# an IPv6 link-local address (its host half is derived from the MAC), a MAC,
# and a hardware serial. The serial pattern is anchored on the word rather
# than on its shape: a bare run of capitals matches ESTABLISHED.
shapes=(
	'[a-z0-9._-]+@[a-z0-9.-]+\.(local|lan|home)'
	'([0-9a-f]{2}:){5}[0-9a-f]{2}'
	'[Ss]erial([ _-]?[Nn]umber)?[^A-Za-z0-9]+[A-Z0-9]{8,}'
)

found=0
report() { found=1; printf '%s\n' "$1"; }

body=$(cat -- "$input")

for p in "${patterns[@]}"; do
	while IFS= read -r line; do
		[[ -n "$line" ]] && report "  name '$p' -> $line"
	done < <(printf '%s\n' "$body" | grep -nF -- "$p" || true)
done

# A /Users path is only a finding when it names someone other than the agreed
# synthetic user, so the placeholder does not trip its own check.
while IFS= read -r line; do
	[[ -n "$line" ]] && report "  real home path -> $line"
done < <(printf '%s\n' "$body" | grep -nE '/Users/[A-Za-z0-9._-]+' | grep -vE '/Users/(alex|user|you)\b' || true)

# A link-local address carries the MAC in its host half, so any of them is a
# finding except the agreed placeholder - the same exemption /Users/alex has.
while IFS= read -r line; do
	[[ -n "$line" ]] && report "  link-local address -> $line"
done < <(printf '%s\n' "$body" | grep -nE 'fe80:[0-9a-f]*:[0-9a-f:]+' | grep -vE 'fe80::1\b' || true)

# Third-party software names. Not a machine identifier, but an inventory of
# what this person chose to install, which is the hole that let Tailscale,
# Raycast, Notion and a Claude Code plugin called i-have-adhd reach published
# GIFs while every check above passed. This is a list, not detection: it holds
# what has actually been found in a capture here, and it grows when the next
# one turns something up. Apple's own names are deliberately absent, because a
# process every Mac runs identifies nobody. Docker is absent for the same
# reason from the other side: Raccoon has a `docker` subcommand, so the word is
# part of the tool's own vocabulary, and flagging it on every run of `rcc
# docker` would train a reader to ignore the check.
third_party=(
	AutoRaise Adobe Alfred Arc Chrome CleanMyMac Cursor Dia Discord DockDoor
	Dropbox Figma Firefox Hammerspoon Karabiner Mullvad NordVPN Notion
	Obsidian OrbStack Parallels Proton Raycast Rectangle Slack Spotify Steam
	Tailscale Telegram VMware WhatsApp WireGuard Zoom iStat 1Password
	i-have-adhd superpowers caveman ponytail impeccable skillreaper v2ray
)
for name in "${third_party[@]}"; do
	while IFS= read -r line; do
		[[ -n "$line" ]] && report "  third-party name '$name' -> $line"
	# -i because startup prints Tailscale as io.tailscale.ipn.macsys, and -w
	# because without it "Arc" matches "research-tool" and "Dia" matches
	# "mediaanalysisd", which is how a check earns being ignored.
	done < <(printf '%s\n' "$body" | grep -inwF -- "$name" || true)
done

for s in "${shapes[@]}"; do
	while IFS= read -r line; do
		[[ -n "$line" ]] && report "  shape '$s' -> $line"
	done < <(printf '%s\n' "$body" | grep -nE -- "$s" || true)
done

if (( found )); then
	echo "preflight: capture names this machine, do not ship it" >&2
	exit 1
fi
exit 0
