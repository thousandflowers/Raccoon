#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_history_help() {
	print_help_header "history" "Shell command history per shell, recent commands" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
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
		;;
	*)
		;;
	esac
done

main() {
	print_step 1 1 "History"

	local zsh_history="$HOME/.zsh_history"
	local zsh_lines=0
	if [[ -f "$zsh_history" ]]; then
		zsh_lines=$(wc -l < "$zsh_history" | xargs || echo "0")
	fi
	local bash_history="$HOME/.bash_history"
	local bash_lines=0
	if [[ -f "$bash_history" ]]; then
		bash_lines=$(wc -l < "$bash_history" | xargs || echo "0")
	fi
	local fish_history="$HOME/.local/share/fish/history/default"
	local fish_lines=0
	if [[ -f "$fish_history" ]]; then
		fish_lines=$(wc -l < "$fish_history" 2>/dev/null | xargs || echo "0")
	fi
	local total=$((zsh_lines + bash_lines + fish_lines))

	print_table_header "Shell|Commands" 13 13
	print_table_row "zsh|$zsh_lines" 13 13
	print_table_row "bash|$bash_lines" 13 13
	print_table_row "fish|$fish_lines" 13 13
	print_table_row "Total|$total" 13 13

	echo ""
	print_info "Recent commands (last 20 entries):"

	local recent_count=0
	if [[ -f "$zsh_history" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ -z "$line" ]] && continue
			local cmd
			cmd=$(echo "$line" | awk '{print $1}' | xargs || echo "")
			[[ -n "$cmd" ]] && {
				print_info "$cmd"
				((recent_count++)) || true
				[[ $recent_count -ge 5 ]] && break
			}
		done < <(tail -n 20 "$zsh_history" 2>/dev/null)
	fi

	if [[ $recent_count -eq 0 ]]; then
		print_info "No recent commands found"
	fi

	echo ""
	print_success "Completed"
}

main "$@"