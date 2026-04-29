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
	printf "| %-40s |\n" "~/Library/LaunchAgents/"
	echo "${GRAY}| ${NC}$(printf '%s' "$(printf ' %.0s' {1..40})" | tr ' ' '-') | ${NC}"

	local user_agents
	user_agents=$(ls -1 ~/Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$user_agents" ]]; then
		local count=0
		while IFS= read -r item; do
			[[ -z "$item" ]] && continue
			local name
			name=$(echo "$item" | sed 's/.plist//' | sed 's/com.//' | sed 's/.//')
			printf "| %-40s |\n" "✓ $name"
			((count++)) || true
		done <<< "$user_agents"
		printf "| ${GRAY}%-40s${NC} |\n" "Total: $count items"
	else
		printf "| ${GRAY}%-40s${NC} |\n" "no user launch agents"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/6] System LaunchAgents...${NC}"
	printf "| %-40s |\n" "/Library/LaunchAgents/"
	echo "${GRAY}| ${NC}$(printf '%s' "$(printf ' %.0s' {1..40})" | tr ' ' '-') | ${NC}"

	local sys_agents
	sys_agents=$(ls -1 /Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$sys_agents" ]]; then
		local count
		count=$(echo "$sys_agents" | wc -l | xargs || echo "0")
		printf "| %-40s |\n" "$count system launch agents"
	else
		printf "| ${GRAY}%-40s${NC} |\n" "none found"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/6] LaunchDaemons...${NC}"
	printf "| %-40s |\n" "/Library/LaunchDaemons/"
	echo "${GRAY}| ${NC}$(printf '%s' "$(printf ' %.0s' {1..40})" | tr ' ' '-') | ${NC}"

	local daemons
	daemons=$(ls -1 /Library/LaunchDaemons/ 2>/dev/null || echo "")
	if [[ -n "$daemons" ]]; then
		local count
		count=$(echo "$daemons" | wc -l | xargs || echo "0")
		printf "| %-40s |\n" "$count launch daemons"
	else
		printf "| ${GRAY}%-40s${NC} |\n" "none found"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/6] Login Items...${NC}"
	printf "| %-40s |\n" "(System Settings > Login Items)"
	echo "${GRAY}| ${NC}$(printf '%s' "$(printf ' %.0s' {1..40})" | tr ' ' '-') | ${NC}"

	local login_items
	login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")
	if [[ -n "$login_items" && "$login_items" != "" ]]; then
		echo "$login_items" | tr ',' '\n' | while read -r item; do
			[[ -z "$item" ]] && continue
			printf "| %-40s |\n" "✓ $item"
		done
	else
		printf "| ${GRAY}%-40s${NC} |\n" "no login items configured"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[5/6] Running Services...${NC}"
	printf "| %-40s |\n" "(launchctl list)"
	echo "${GRAY}| ${NC}$(printf '%s' "$(printf ' %.0s' {1..40})" | tr ' ' '-') | ${NC}"

	local running
	running=$(launchctl list 2>/dev/null | tail -n +2 | wc -l | xargs || echo "0")
	printf "| %-40s |\n" "Running services: $running"
	printf "| ${GRAY}%-40s${NC} |\n" "Top 5:"
	launchctl list 2>/dev/null | tail -n +2 | head -5 | awk '{printf "| %-40s |\n", "  " $3 " (" $1 ")"}' || true
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[6/6] System Uptime...${NC}"
	printf "| %-40s |\n" "(uptime)"
	echo "${GRAY}| ${NC}$(printf '%s' "$(printf ' %.0s' {1..40})" | tr ' ' '-') | ${NC}"

	local uptime
	uptime=$(uptime 2>/dev/null || echo "N/A")
	local load
	load=$(uptime 2>/dev/null | grep "load" | sed 's/.*load //' | sed 's/,//g' || echo "N/A")
	printf "| %-40s |\n" "$uptime"
	if [[ -n "$load" ]]; then
		printf "| %-40s |\n" "Load average: $load"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"