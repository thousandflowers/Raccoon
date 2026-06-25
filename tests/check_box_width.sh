#!/bin/bash
# Read audit output on stdin; exit 0 iff every box line (+ or | prefix, ANSI
# stripped) has the same display width. Guards against the ragged-report bug.
# Pure Bash replacement for check_box_width.py.
#
# A UTF-8 locale is forced so ${#clean} counts code points (the box rows contain
# ✓ ⚠ ✗), matching Python's len(). The ANSI strip uses a real ESC byte ($'\x1b')
# so it works on BSD sed (macOS), not just GNU sed.

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

first=""
ragged=0
seen=""

while IFS= read -r line || [[ -n "$line" ]]; do
	clean="$(printf '%s' "$line" | sed $'s/\x1b\\[[0-9;]*m//g')"
	[[ -z "$clean" ]] && continue
	case "$clean" in
	[+\|]*) ;;
	*) continue ;;
	esac
	w=${#clean}
	if [[ -z "$first" ]]; then
		first="$w"
		seen="$w"
	elif [[ "$w" != "$first" ]]; then
		ragged=1
		seen="$seen $w"
	fi
done

if [[ "$ragged" -eq 0 ]]; then
	echo "OK"
	exit 0
fi

echo "RAGGED: widths seen: $seen" >&2
exit 1
