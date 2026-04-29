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

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_history_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Shell History"

	echo "+-------------+------------+"
	echo "| Shell      | Commands   |"
	echo "+-------------+------------+"

	local zsh_history="$HOME/.zsh_history"
	local zsh_lines=0
	if [[ -f "$zsh_history" ]]; then
		zsh_lines=$(wc -l < "$zsh_history" | xargs || echo "0")
	fi
	printf "| ${CYAN}%-9s${NC} | %9s |\n" "zsh" "$zsh_lines"

	local bash_history="$HOME/.bash_history"
	local bash_lines=0
	if [[ -f "$bash_history" ]]; then
		bash_lines=$(wc -l < "$bash_history" | xargs || echo "0")
	fi
	printf "| ${CYAN}%-9s${NC} | %9s |\n" "bash" "$bash_lines"

	local fish_history="$HOME/.local/share/fish/history/default"
	local fish_lines=0
	if [[ -f "$fish_history" ]]; then
		fish_lines=$(wc -l < "$fish_history" 2>/dev/null | xargs || echo "0")
	fi
	printf "| ${CYAN}%-9s${NC} | %9s |\n" "fish" "$fish_lines"

	echo "+-------------+------------+"

	local total=$((zsh_lines + bash_lines + fish_lines))
	printf "| ${GRAY}Total${NC}     | %9s |\n" "$total"

	echo "+-------------+------------+"

	echo ""
	echo "+-------------------------------------+"
	echo "| Recent Commands                     |"
	echo "+-------------------------------------+"

	local recent_count=0
	if [[ -f "$zsh_history" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ -z "$line" ]] && continue
			local cmd
			cmd=$(echo "$line" | awk '{print $1}' | xargs || echo "")
			[[ -n "$cmd" ]] && {
				printf "│ %-34s │\n" "$cmd"
				((recent_count++)) || true
				[[ $recent_count -ge 5 ]] && break
			}
		done < <(tail -n 20 "$zsh_history" 2>/dev/null)
	fi

	if [[ $recent_count -eq 0 ]]; then
		echo "│ ${GRAY}No recent commands${NC}            │"
	fi

	echo "+-------------------------------------+"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"