#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

BIN_PATH="$SCRIPT_DIR"

items=(
	"upgrade:upgrade.sh:Upgrade system & apps"
	"audit:audit.sh:Security audit"
	"network:network.sh:Network status"
	"disk:disk.sh:Disk info"
	"memory:memory.sh:Memory usage"
	"ssh:ssh.sh:SSH keys"
	"git:git.sh:Git repos"
	"ports:ports.sh:Open ports"
	"battery:battery.sh:Battery status"
	"backup:backup.sh:Backup status"
	"env:env.sh:Environment"
	"startup:startup.sh:Startup items"
	"trash:trash.sh:Trash management"
	"fonts:fonts.sh:Font management"
	"history:history.sh:Shell history"
	"certs:certs.sh:SSL certificates"
	"docker:docker.sh:Docker status"
	"xcode:xcode.sh:Xcode tools"
)

cols=4
selected=0

render() {
	clear 2>/dev/null || true
	echo ""
	echo "${CYAN}Raccoon${NC}"
	echo "macOS companion toolkit"
	echo ""
	
	local idx=0
	for row in $(seq 0 4); do
		for col in $(seq 0 $((cols-1))); do
			if [[ $idx -lt ${#items[@]} ]]; then
				local item="${items[$idx]}"
				local title="${item%%:*}"
				if [[ $idx -eq $selected ]]; then
					echo -n " ${GREEN}[$title]${NC} "
				else
					echo -n " $title "
				fi
				((idx++)) || true
			fi
		done
		echo ""
	done
	echo ""
	echo "${GRAY}←→ Navigate · ↑↓ Rows · Enter Run · / Search · Q Quit${NC}"
}

run_item() {
	local idx=$1
	local item="${items[$idx]}"
	local cmd="${item#*:}"
	cmd="${cmd%%:*}"
	if [[ -n "$cmd" && -x "$BIN_PATH/$cmd" ]]; then
		"$BIN_PATH/$cmd"
	fi
}

_filter_items() {
	local query="$1"
	local lower_query
	lower_query=$(echo "$query" | tr '[:upper:]' '[:lower:]')
	
	local -a filtered=()
	local n=0
	for item in "${items[@]}"; do
		local lower_item
		lower_item=$(echo "$item" | tr '[:upper:]' '[:lower:]')
		if [[ "$lower_item" == *"$lower_query"* ]]; then
			filtered+=("$n:$item")
		fi
		n=$((n+1))
	done
	
	echo "${filtered[@]}"
}

_render_filtered() {
	local sel="$1"
	shift
	local -a filtered=("$@")
	
	clear 2>/dev/null || true
	echo ""
	echo "${CYAN}Raccoon${NC}"
	echo "macOS companion toolkit"
	echo ""
	
	local n=1
	for item in "${filtered[@]}"; do
		local orig_idx="${item%%:*}"
		local rest="${item#*:}"
		local title="${rest%%:*}"
		local desc="${rest#*:}"
		desc="${desc#*:}"
		
		if [[ $n -eq $sel ]]; then
			echo -e " ${GREEN}[$n] $title${NC} — $desc"
		else
			echo "  $n. $title — $desc"
		fi
		n=$((n+1))
	done
	
	echo ""
	echo -e "${GRAY}↑↓ Navigate · Enter Run · Esc Cancel${NC}"
}

_search_and_run() {
	echo ""
	echo -n "Search: "
	read -r query
	
	if [[ -z "$query" ]]; then
		return 1
	fi
	
	local result
	result=$(_filter_items "$query")
	local -a filtered=($result)
	
	if [[ ${#filtered[@]} -eq 0 ]]; then
		echo ""
		echo -e "${YELLOW}No matches found${NC}"
		echo ""
		echo -n "Press any key to continue..."
		read -r -s -n 1
		return 1
	fi
	
	if [[ ${#filtered[@]} -eq 1 ]]; then
		local orig_idx="${filtered[0]%%:*}"
		run_item "$orig_idx"
		return 0
	fi
	
	local sel=1
	while true; do
		_render_filtered "$sel" "${filtered[@]}"
		
		read -r -s -n 1 key
		case "$key" in
			$'\x1b')
				read -r -s -n 1 rest || true
				if [[ "$rest" == "[" ]]; then
					read -r -s -n 1 arrow || true
					case "$arrow" in
						A) ((sel > 1)) && sel=$((sel-1)) ;;
						B) ((sel < ${#filtered[@]})) && sel=$((sel+1)) ;;
					esac
				fi
				;;
			$'\n'|$'\r')
				local chosen="${filtered[$((sel-1))]}"
				local orig_idx="${chosen%%:*}"
				run_item "$orig_idx"
				return 0
				;;
			$'\x03'|q|Q)
				return 1
				;;
		esac
	done
}

main() {
	render
	
	while true; do
		read -r -s -n 1 key || break
		
		case "$key" in
			q|Q)
				break
				;;
			$'\x1b')
				read -r -s -n 1 rest || true
				if [[ "$rest" == "[" ]]; then
					read -r -s -n 1 arrow || true
					case "$arrow" in
						D) ((selected > 0)) && ((selected--)) || true ;;
						C) ((selected < ${#items[@]}-1)) && ((selected++)) || true ;;
						A) ((selected >= cols)) && ((selected-=cols)) || true ;;
						B) next=$((selected + cols)); ((next < ${#items[@]})) && selected=$next || true ;;
					esac
				fi
				;;
			$'\n'|$'\r')
				run_item $selected
				;;
			/)
				_search_and_run
				;;
		esac
		
		render
	done
	
	clear 2>/dev/null || true
}

main "$@"