#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_startup_help() {
	print_help_header "startup" "Launch agents, login items, running services, uptime" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
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

	print_step 1 6 "User LaunchAgents"
	print_table_header "Name" 40

	local user_agents
	user_agents=$(ls -1 ~/Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$user_agents" ]]; then
		local count=0
		while IFS= read -r item; do
			[[ -z "$item" ]] && continue
			local name
			name=$(echo "$item" | sed 's/.plist//' | sed 's/com.//' | sed 's/.//')
			print_table_row "$name" 40
			((count++)) || true
		done <<< "$user_agents"
		print_info "Total: $count items"
	else
		print_info "no user launch agents"
	fi
	print_success "User LaunchAgents checked"

	print_step 2 6 "System LaunchAgents"

	local sys_agents
	sys_agents=$(ls -1 /Library/LaunchAgents/ 2>/dev/null || echo "")
	if [[ -n "$sys_agents" ]]; then
		local count
		count=$(echo "$sys_agents" | wc -l | xargs || echo "0")
		print_info "$count system launch agents"
	else
		print_info "none found"
	fi
	print_success "System LaunchAgents checked"

	print_step 3 6 "LaunchDaemons"

	local daemons
	daemons=$(ls -1 /Library/LaunchDaemons/ 2>/dev/null || echo "")
	if [[ -n "$daemons" ]]; then
		local count
		count=$(echo "$daemons" | wc -l | xargs || echo "0")
		print_info "$count launch daemons"
	else
		print_info "none found"
	fi
	print_success "LaunchDaemons checked"

	print_step 4 6 "Login Items"

	local login_items
	login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")
	if [[ -n "$login_items" && "$login_items" != "" ]]; then
		echo "$login_items" | tr ',' '\n' | while read -r item; do
			[[ -z "$item" ]] && continue
			print_info "$item"
		done
	else
		print_info "no login items configured"
	fi
	print_success "Login Items checked"

	print_step 5 6 "Running Services"

	local running
	running=$(launchctl list 2>/dev/null | tail -n +2 | wc -l | xargs || echo "0")
	print_info "Running services: $running"
	print_info "Top 5:"
	launchctl list 2>/dev/null | tail -n +2 | head -5 | awk '{print "  " $3 " (" $1 ")"}' || true
	print_success "Services checked"

	print_step 6 6 "System Uptime"

	local uptime
	uptime=$(uptime 2>/dev/null || echo "N/A")
	local load
	load=$(uptime 2>/dev/null | grep "load" | sed 's/.*load //' | sed 's/,//g' || echo "N/A")
	print_info "$uptime"
	if [[ -n "$load" ]]; then
		print_info "Load average: $load"
	fi
	print_success "Uptime checked"

	echo ""
	print_success "Completed"
}

main "$@"