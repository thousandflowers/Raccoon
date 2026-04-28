#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_startup_help() {
	echo "Usage: rcc startup [options]"
	echo ""
	echo "Show startup items, launch agents, and login items"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_startup_help
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
	print_section_header "Startup Items"

	echo "${GRAY}[1/6] User LaunchAgents...${NC}"
	echo "${GRAY}~/Library/LaunchAgents/${NC}"
	local user_agents
	user_agents=$(ls -1 ~/Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$user_agents" ]]; then
		local count=0
		while IFS= read -r item; do
			[[ -z "$item" ]] && continue
			local name
			name=$(echo "$item" | sed 's/.plist//' | sed 's/com.//' | sed 's/.//')
			echo "  ✓ $name"
			((count++))
		done <<< "$user_agents"
		echo "  Total: $count items"
	else
		echo "  ${GRAY}no user launch agents${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/6] System LaunchAgents...${NC}"
	echo "${GRAY}/Library/LaunchAgents/${NC}"
	local sys_agents
	sys_agents=$(ls -1 /Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$sys_agents" ]]; then
		local count
		count=$(echo "$sys_agents" | wc -l | xargs || echo "0")
		echo "  $count system launch agents"
	else
		echo "  ${GRAY}none found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/6] LaunchDaemons...${NC}"
	echo "${GRAY}/Library/LaunchDaemons/${NC}"
	local daemons
	daemons=$(ls -1 /Library/LaunchDaemons/ 2>/dev/null || echo "")
	if [[ -n "$daemons" ]]; then
		local count
		count=$(echo "$daemons" | wc -l | xargs || echo "0")
		echo "  $count launch daemons"
	else
		echo "  ${GRAY}none found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/6] Login Items...${NC}"
	echo "${GRAY}(System Settings > Login Items)${NC}"
	local login_items
	login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")
	if [[ -n "$login_items" && "$login_items" != "" ]]; then
		echo "$login_items" | tr ',' '\n' | while read -r item; do
			[[ -z "$item" ]] && continue
			echo "  ✓ $item"
		done
	else
		echo "  ${GRAY}no login items configured${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[5/6] Running Services (launchctl)...${NC}"
	local running
	running=$(launchctl list 2>/dev/null | tail -n +2 | wc -l | xargs || echo "0")
	echo "  Running services: $running"
	echo "  ${GRAY}Top 5:${NC}"
	launchctl list 2>/dev/null | tail -n +2 | head -5 | awk '{print "  " $3 " (" $1 ")"}' || true
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[6/6] System Uptime...${NC}"
	local uptime
	uptime=$(uptime 2>/dev/null || echo "N/A")
	local load
	load=$(uptime 2>/dev/null | grep "load" | sed 's/.*load //' | sed 's/,//g' || echo "N/A")
	echo "  $uptime"
	if [[ -n "$load" ]]; then
		echo "  Load average: $load"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"