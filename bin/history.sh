#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_history_help() {
	echo "Usage: rcc history [options]"
	echo ""
	echo "Show shell command history"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

# shellcheck disable=SC2034
JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_history_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		shift
		;;
	*)
		;;
	esac
done

# Where each shell keeps its history, in one place. Both the JSON and the text
# report used to spell these out separately, and both spelled fish wrong:
# ~/.local/share/fish/history/default is not a path any version of fish writes.
# A fish user's count was therefore always 0, reported as confidently as a real
# number.
_HIST_ZSH="$HOME/.zsh_history"
_HIST_BASH="$HOME/.bash_history"
# fish 3.x and later, default session. A `fish_history` variable renames it to
# <session>_history, which is rare enough to leave alone but is why this is not
# simply "the file in that folder".
_HIST_FISH="$HOME/.local/share/fish/fish_history"

_history_lines() {
	[[ -f "$1" ]] || { printf '0'; return 0; }
	wc -l < "$1" 2>/dev/null | tr -d ' \n' || printf '0'
}

# fish writes two lines per command — `- cmd: ...` then `  when: ...` — so
# counting lines reports twice what the user typed. Count the entries.
_history_lines_fish() {
	[[ -f "$1" ]] || { printf '0'; return 0; }
	# `grep -c` exits 1 when it counts nothing, which under set -e would take
	# the script with it. Same trap as everywhere else in this repository.
	local n
	n=$(grep -c '^- cmd:' "$1" 2>/dev/null || true)
	printf '%s' "$((n))"
}

# The recent commands, first word only: the rest of a line is arguments, and
# arguments are where paths and secrets live.
_history_recent() {
	local line cmd n=0
	[[ -f "$1" ]] || return 0
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "$line" ]] && continue
		cmd=$(printf '%s' "$line" | sed 's/^: [0-9]*:[0-9]*;//' | awk '{print $1}')
		[[ -z "$cmd" ]] && continue
		printf '%s\n' "$cmd"
		n=$((n + 1))
		[[ $n -ge 5 ]] && break
	done < <(tail -n 20 "$1" 2>/dev/null)
	return 0
}

_json_report() {
	local zsh_h="$_HIST_ZSH" bash_h="$_HIST_BASH"
	local z b f cmd first=1
	z=$(_history_lines "$zsh_h")
	b=$(_history_lines "$bash_h")
	f=$(_history_lines_fish "$_HIST_FISH")
	printf '{\n'
	printf '  "counts": {"zsh": %s, "bash": %s, "fish": %s, "total": %s},\n' \
		"$z" "$b" "$f" "$((z + b + f))"
	printf '  "recent": ['
	while IFS= read -r cmd; do
		[[ -z "$cmd" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$cmd")"
	done < <(_history_recent "$zsh_h")
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	print_section_header "Shell History"

	echo "${GRAY}[1/2] Command Counts...${NC}"
	print_table_header "Shell|Commands" 10 10

	# The same three helpers the JSON uses, so the two reports cannot disagree
	# about one machine — which they did, both being wrong about fish.
	local zsh_lines bash_lines fish_lines
	zsh_lines=$(_history_lines "$_HIST_ZSH")
	print_table_row "zsh|$zsh_lines" 10 10

	bash_lines=$(_history_lines "$_HIST_BASH")
	print_table_row "bash|$bash_lines" 10 10

	fish_lines=$(_history_lines_fish "$_HIST_FISH")
	print_table_row "fish|$fish_lines" 10 10

	local total=$((zsh_lines + bash_lines + fish_lines))
	print_table_row "${GRAY}Total${NC}|$total" 10 10
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/2] Recent Commands...${NC}"
	print_table_header "Recent Command" 35

	local recent_count=0
	if [[ -f "$_HIST_ZSH" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ -z "$line" ]] && continue
			local cmd
			cmd=$(echo "$line" | sed 's/^: [0-9]*:[0-9]*;//' | awk '{print $1}' | xargs || echo "")
			[[ -n "$cmd" ]] && {
				print_table_row "$cmd" 35
				((recent_count++)) || true
				[[ $recent_count -ge 5 ]] && break
			}
		done < <(tail -n 20 "$_HIST_ZSH" 2>/dev/null)
	fi

	if [[ $recent_count -eq 0 ]]; then
		print_table_row "${GRAY}No recent commands${NC}" 35
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
