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

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_history_help
		exit 0
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Shell History"

	echo "${GRAY}[1/2] Command Counts...${NC}"
	print_table_header "Shell|Commands" 10 10

	local zsh_history="$HOME/.zsh_history"
	local zsh_lines=0
	if [[ -f "$zsh_history" ]]; then
		zsh_lines=$(wc -l < "$zsh_history" | xargs || echo "0")
	fi
	print_table_row "zsh|$zsh_lines" 10 10

	local bash_history="$HOME/.bash_history"
	local bash_lines=0
	if [[ -f "$bash_history" ]]; then
		bash_lines=$(wc -l < "$bash_history" | xargs || echo "0")
	fi
	print_table_row "bash|$bash_lines" 10 10

	local fish_history="$HOME/.local/share/fish/history/default"
	local fish_lines=0
	if [[ -f "$fish_history" ]]; then
		fish_lines=$(wc -l < "$fish_history" 2>/dev/null | xargs || echo "0")
	fi
	print_table_row "fish|$fish_lines" 10 10

	local total=$((zsh_lines + bash_lines + fish_lines))
	print_table_row "${GRAY}Total${NC}|$total" 10 10
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/2] Recent Commands...${NC}"
	print_table_header "Recent Command" 35

	local recent_count=0
	if [[ -f "$zsh_history" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ -z "$line" ]] && continue
			local cmd
			cmd=$(echo "$line" | sed 's/^: [0-9]*:[0-9]*;//' | awk '{print $1}' | xargs || echo "")
			[[ -n "$cmd" ]] && {
				print_table_row "$cmd" 35
				((recent_count++)) || true
				[[ $recent_count -ge 5 ]] && break
			}
		done < <(tail -n 20 "$zsh_history" 2>/dev/null)
	fi

	if [[ $recent_count -eq 0 ]]; then
		print_table_row "${GRAY}No recent commands${NC}" 35
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
