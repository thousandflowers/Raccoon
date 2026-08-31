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
	'fe80::[0-9a-f:]+'
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
