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
	printf "\033[2J\033[H"
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
	echo "${GRAY}←→ Navigate · ↑↓ Rows · Enter Run · Q Quit${NC}"
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
		esac
		
		render
	done
	
	printf "\033[2J\033[H"
}

main "$@"