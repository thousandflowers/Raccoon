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
	echo "  --clean         Remove orphaned launch agents (interactive, with backup)"
	echo "  --help, -h      Show this help"
	echo ""
	echo "Examples:"
	echo "  rcc startup            # list startup items and launch agents"
	echo "  rcc startup clean      # find and remove orphaned user launch agents"
}

# shellcheck disable=SC2034
JSON_OUTPUT=false
CLEAN_MODE=false
ORPHAN_PLISTS=()

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_startup_help
		exit 0
		;;
	--json)
		;;
	--clean)
		CLEAN_MODE=true
		;;
	*)
		;;
	esac
done

# Extract the executable (first <string> after <key>ProgramArguments</key>) from
# a launch-agent plist using only awk — no plistutil/xmllint/python.
_agent_program() {
	awk '
		/<key>ProgramArguments<\/key>/ { in_pa = 1; next }
		in_pa && /<string>/ {
			line = $0
			sub(/.*<string>/, "", line)
			sub(/<\/string>.*/, "", line)
			print line
			exit
		}
	' "$1" 2>/dev/null
}

# Collect orphaned user launch agents into ORPHAN_PLISTS: those whose executable
# is an absolute path that no longer exists on disk. NEVER touches system-level
# /Library agents (this only scans ~/Library/LaunchAgents), and treats agents
# whose binary lives under /System or /usr as valid (they may be hidden).
find_orphan_agents() {
	ORPHAN_PLISTS=()
	local dir="$HOME/Library/LaunchAgents"
	[[ -d "$dir" ]] || return 0
	local plist exe
	for plist in "$dir"/*.plist; do
		[[ -e "$plist" ]] || continue
		exe="$(_agent_program "$plist")"
		[[ -z "$exe" ]] && continue           # can't determine target -> leave it
		case "$exe" in
			/System/* | /usr/*) continue ;;   # system agents -> not orphan
			/*) ;;                            # absolute path -> evaluate
			*) continue ;;                    # non-absolute -> can't verify
		esac
		if [[ ! -x "$exe" && ! -f "$exe" ]]; then
			ORPHAN_PLISTS+=("$plist")
		fi
	done
}

show_orphan_agents() {
	echo "${YELLOW}Orphaned launch agents found:${NC}"
	local plist exe
	for plist in ${ORPHAN_PLISTS[@]+"${ORPHAN_PLISTS[@]}"}; do
		exe="$(_agent_program "$plist")"
		echo "  ${plist##*/}"
		echo "    ${GRAY}missing: $exe${NC}"
	done
}

# Interactively remove each orphan. Mirrors audit's --fix safety: back up the
# plist to ~/.raccoon/fix-backups/<timestamp>/ before unloading and deleting.
remove_orphan_agents() {
	local backup_dir plist label answer
	backup_dir="$HOME/.raccoon/fix-backups/$(date +%Y%m%d-%H%M%S)"
	for plist in ${ORPHAN_PLISTS[@]+"${ORPHAN_PLISTS[@]}"}; do
		label="${plist##*/}"
		printf '  -> Remove %s? [y/N] ' "$label"
		read -r answer || answer="n"
		if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
			mkdir -p "$backup_dir"
			cp "$plist" "$backup_dir/" 2>/dev/null || true
			launchctl unload "$plist" 2>/dev/null || true
			rm -f "$plist"
			echo "    ${GREEN}✓ Removed${NC} ${GRAY}(backup: $backup_dir)${NC}"
		else
			echo "    ${GRAY}skip${NC}"
		fi
	done
}

main() {
	if [[ "$CLEAN_MODE" == "true" ]]; then
		print_section_header "Clean Orphaned Launch Agents"
		find_orphan_agents
		if [[ ${#ORPHAN_PLISTS[@]} -eq 0 ]]; then
			echo "${GREEN}No orphaned launch agents found.${NC}"
			return 0
		fi
		show_orphan_agents
		echo ""
		local answer
		printf 'Proceed with interactive removal? [y/N] '
		read -r answer || answer="n"
		if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
			remove_orphan_agents
		else
			echo "${GRAY}Cancelled.${NC}"
		fi
		return 0
	fi

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
			name=$(echo "$item" | sed -E 's/^[^.]+\.[^.]+\.//' | sed 's/\.plist$//')
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
	done || true
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[6/6] System Uptime...${NC}"
	print_table_header "Metric" 40

	local uptime_str
	uptime_str=$(uptime 2>/dev/null | sed 's/.*up \(.*\), [0-9]* user.*/\1/' || echo "N/A")
	local load
	load=$(uptime 2>/dev/null | awk -F'load averages?: ' '{print $2}' | sed 's/,//g' || echo "N/A")
	print_table_row "Uptime: $uptime_str" 40
	if [[ -n "$load" && "$load" != "N/A" ]]; then
		print_table_row "Load: $load" 40
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
