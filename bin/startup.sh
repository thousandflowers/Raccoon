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
	print_table_header "Item" 40

	local user_agents
	user_agents=$(ls -1 ~/Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$user_agents" ]]; then
		local count=0
		while IFS= read -r item; do
			[[ -z "$item" ]] && continue
			local name
			name=$(echo "$item" | sed 's/.plist//' | sed 's/com.//' | sed 's/.//')
			print_table_row "✓ $name" 40
			((count++)) || true
		done <<< "$user_agents"
		print_table_row "${GRAY}Total: $count items${NC}" 40
	else
		print_table_row "${GRAY}no user launch agents${NC}" 40
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/6] System LaunchAgents...${NC}"
	print_table_header "Source|Count" 30 10

	local sys_agents
	sys_agents=$(ls -1 /Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$sys_agents" ]]; then
		local count
		count=$(echo "$sys_agents" | wc -l | xargs || echo "0")
		print_table_row "/Library/LaunchAgents/|$count" 30 10
	else
		print_table_row "${GRAY}none found${NC}|0" 30 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/6] LaunchDaemons...${NC}"
	print_table_header "Source|Count" 30 10

	local daemons
	daemons=$(ls -1 /Library/LaunchDaemons/ 2>/dev/null || echo "")
	if [[ -n "$daemons" ]]; then
		local count
		count=$(echo "$daemons" | wc -l | xargs || echo "0")
		print_table_row "/Library/LaunchDaemons/|$count" 30 10
	else
		print_table_row "${GRAY}none found${NC}|0" 30 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/6] Login Items...${NC}"
	print_table_header "Item" 40

	local login_items
	login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")
	if [[ -n "$login_items" && "$login_items" != "" ]]; then
		echo "$login_items" | tr ',' '\n' | while read -r item; do
			[[ -z "$item" ]] && continue
			print_table_row "✓ $item" 40
		done
	else
		print_table_row "${GRAY}no login items configured${NC}" 40
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[5/6] Running Services...${NC}"
	print_table_header "Service|PID" 35 10

	local running
	running=$(launchctl list 2>/dev/null | tail -n +2 | wc -l | xargs || echo "0")
	print_table_row "Total running services|$running" 35 10
	launchctl list 2>/dev/null | tail -n +2 | head -5 | awk '{print $3 "|" $1}' | while IFS='|' read -r svc pid; do
		[[ -n "$svc" ]] && print_table_row "$svc|$pid" 35 10
	done
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[6/6] System Uptime...${NC}"
	print_table_header "Metric" 40

	local uptime
	uptime=$(uptime 2>/dev/null || echo "N/A")
	local load
	load=$(uptime 2>/dev/null | grep "load" | sed 's/.*load //' | sed 's/,//g' || echo "N/A")
	print_table_row "$uptime" 40
	if [[ -n "$load" && "$load" != "N/A" ]]; then
		print_table_row "Load average: $load" 40
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
