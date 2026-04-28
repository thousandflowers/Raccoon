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

	echo "${GRAY}[1/3] zsh History...${NC}"
	local zsh_history="$HOME/.zsh_history"
	if [[ -f "$zsh_history" ]]; then
		local zsh_lines
		zsh_lines=$(wc -l < "$zsh_history" | xargs || echo "0")
		printf "  Lines: %s\n" "$zsh_lines"
		echo "  ${GRAY}Recent commands:${NC}"
		tail -n 10 "$zsh_history" 2>/dev/null | head -5 | while read -r line; do
			[[ -z "$line" ]] && continue
			local cmd
			cmd=$(echo "$line" | awk '{print $1}' | xargs || echo "")
			[[ -n "$cmd" ]] && echo "    $cmd"
		done
	else
		echo "  ${GRAY}no zsh history found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/3] bash History...${NC}"
	local bash_history="$HOME/.bash_history"
	if [[ -f "$bash_history" ]]; then
		local bash_lines
		bash_lines=$(wc -l < "$bash_history" | xargs || echo "0")
		printf "  Lines: %s\n" "$bash_lines"
	else
		echo "  ${GRAY}no bash history found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/3] Fish History...${NC}"
	local term_history="$HOME/.local/share/fish/history/default"
	if [[ -f "$term_history" ]]; then
		local term_lines
		term_lines=$(wc -l < "$term_history" | xargs || echo "0")
		printf "  Lines: %s\n" "$term_lines"
	else
		echo "  ${GRAY}no fish history found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	local total_zsh total_bash
	total_zsh=$(wc -l < "$HOME/.zsh_history" 2>/dev/null | xargs || echo "0")
	total_bash=$(wc -l < "$HOME/.bash_history" 2>/dev/null | xargs || echo "0")
	echo "  ${GRAY}Total commands: $((total_zsh + total_bash))${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"