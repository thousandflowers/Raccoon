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
	echo "  --clean         Remove orphaned launch agents (interactive, with backup)"
	echo "  --json          Output in JSON format"
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
		JSON_OUTPUT=true
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

# The name a person recognises: com.example.thing.plist is the file, "thing"
# is what they installed.
_startup_agent_name() {
	printf '%s' "$1" | sed -E 's/^[^.]+\.[^.]+\.//' | sed 's/\.plist$//'
}

# launchd's own label for a plist. The filename is a convention, not the key:
# com.adobe.GC.Invoker-1.0.plist declares Label com.adobe.GC.Scheduler-1.0, and
# `launchctl bootout` takes the label. Falls back to the filename stem.
_plist_label() {
	local label
	label=$(plutil -extract Label raw -o - "$1" 2>/dev/null || true)
	if [[ -n "$label" ]]; then printf '%s' "$label"; else basename "$1" .plist; fi
}

# The plist launchd actually loaded for a label, or nothing when it is not
# loaded. Two plists can carry one label; only one of them is the job.
_loaded_from() {
	launchctl print "gui/$(id -u)/$1" 2>/dev/null |
		sed -n 's/^[[:space:]]*path = //p' | head -1 || true
}

# `launchctl list` once: pid, status, label per line, header dropped.
_LAUNCHCTL_LIST=""
_launchctl_list() {
	if [[ -z "$_LAUNCHCTL_LIST" ]]; then
		_LAUNCHCTL_LIST=$(launchctl list 2>/dev/null | tail -n +2 || true)
	fi
	printf '%s\n' "$_LAUNCHCTL_LIST"
}

# One line per plist in a directory: label <TAB> file <TAB> loaded_from.
_agents_in() {
	local dir="$1" plist label
	for plist in "$dir"/*.plist; do
		[[ -e "$plist" ]] || continue
		label=$(_plist_label "$plist")
		printf '%s\t%s\t%s\n' "$label" "$plist" "$(_loaded_from "$label")"
	done
}

# Login items as System Events lists them: name <TAB> path, one per line. A
# name may contain a comma, so the script joins on linefeed itself rather than
# handing back a comma-joined list. A target that is gone reads "missing
# value". Prints nothing and fails when System Events refuses (Automation not
# granted), which is a different answer from "none".
_login_items() {
	osascript \
		-e "set AppleScript's text item delimiters to linefeed" \
		-e 'tell application "System Events"' \
		-e '  set out to {}' \
		-e '  repeat with li in login items' \
		-e '    set end of out to (name of li) & tab & (path of li as text)' \
		-e '  end repeat' \
		-e 'end tell' \
		-e 'return out as text'
}

# Services launchd has loaded that no plist in ~/Library or /Library explains:
# registered by an app through SMAppService (System Settings > General > Login
# Items > "Allow in the Background"), loaded from a plist inside an app bundle,
# or left over from a plist that has since moved. Apple's own are left out;
# they are the system, not something that was added. Reads "label <TAB> pid".
_background_items() {
	local known="$1" pid label
	while read -r pid _ label; do
		[[ -n "$label" ]] || continue
		[[ "$label" == com.apple.* ]] && continue
		# launchd keeps one "application.<bundle id>.<n>.<n>" record per app a
		# person has open. Those are windows, not things that start on their own.
		[[ "$label" == application.* ]] && continue
		grep -qxF "$label" <<< "$known" && continue
		# com.openssh.ssh-agent and friends: shipped in /System, not added.
		[[ "$(_loaded_from "$label")" == /System/* ]] && continue
		printf '%s\t%s\n' "$label" "$pid"
	done < <(_launchctl_list)
}

_json_report() {
	local label file from name pid first item path
	local user_agents sys_agents known login_items login_error="" background
	user_agents=$(_agents_in "$HOME/Library/LaunchAgents")
	sys_agents=$(_agents_in /Library/LaunchAgents)
	known=$(printf '%s\n%s\n' "$user_agents" "$sys_agents" | cut -f1)
	background=$(_background_items "$known")
	if ! login_items=$(_login_items 2>&1); then
		login_error="${login_items:-System Events did not answer}"
		login_items=""
	fi

	printf '{\n'

	printf '  "user_agents": ['
	first=1
	while IFS=$'\t' read -r label file from; do
		[[ -n "$label" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		name=$(_startup_agent_name "$(basename "$file")")
		printf '\n    {"label": %s, "name": %s, "file": %s, "loaded": %s, "loaded_from": %s}' \
			"$(rcc_json_string "$label")" "$(rcc_json_string "$name")" \
			"$(rcc_json_string "$file")" "$([[ "$from" == "$file" ]] && echo true || echo false)" \
			"$(rcc_json_string "$from")"
	done <<< "$user_agents"
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "background_items": ['
	first=1
	while IFS=$'\t' read -r label pid; do
		[[ -n "$label" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"label": %s, "pid": %s}' "$(rcc_json_string "$label")" \
			"$([[ "$pid" =~ ^[0-9]+$ ]] && echo "$pid" || echo null)"
	done <<< "$background"
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "login_items": ['
	first=1
	while IFS=$'\t' read -r item path; do
		[[ -n "$item" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$item")"
	done <<< "$login_items"
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	# The ones whose target is gone: they are listed, and nothing opens.
	printf '  "login_items_missing": ['
	first=1
	while IFS=$'\t' read -r item path; do
		[[ -n "$item" && "$path" == "missing value" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$item")"
	done <<< "$login_items"
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'
	printf '  "login_items_error": %s,\n' "$(rcc_json_string "$login_error")"

	local loaded running
	loaded=$(_launchctl_list | grep -c . || true)
	running=$(_launchctl_list | awk '$1 != "-"' | grep -c . || true)
	printf '  "counts": {"system_agents": %s, "system_agents_loaded": %s, "daemons": %s, "running_services": %s, "loaded_services": %s},\n' \
		"$(rcc_json_number "$(printf '%s\n' "$sys_agents" | grep -c . || true)")" \
		"$(rcc_json_number "$(printf '%s\n' "$sys_agents" | awk -F'\t' '$3 != ""' | grep -c . || true)")" \
		"$(rcc_json_number "$(ls -1 /Library/LaunchDaemons/*.plist 2>/dev/null | wc -l | tr -d ' ')")" \
		"$(rcc_json_number "$running")" "$(rcc_json_number "$loaded")"

	local uptime_str load
	uptime_str=$(uptime 2>/dev/null | sed 's/.*up \(.*\), [0-9]* user.*/\1/' || printf '')
	load=$(uptime 2>/dev/null | awk -F'load averages?: ' '{print $2}' | sed 's/,//g' || printf '')
	printf '  "uptime": %s,\n' "$(rcc_json_string "$uptime_str")"
	printf '  "load": %s\n}\n' "$(rcc_json_string "$load")"
}

main() {
	rcc_require_tools launchctl plutil osascript
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
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

	local label file from name pid count item path
	local user_agents sys_agents known background
	user_agents=$(_agents_in "$HOME/Library/LaunchAgents")
	sys_agents=$(_agents_in /Library/LaunchAgents)
	known=$(printf '%s\n%s\n' "$user_agents" "$sys_agents" | cut -f1)

	echo "${GRAY}[1/7] User LaunchAgents...${NC}"
	print_table_header "Item" 60
	if [[ -n "$user_agents" ]]; then
		count=0
		while IFS=$'\t' read -r label file from; do
			[[ -n "$label" ]] || continue
			name=$(_startup_agent_name "$(basename "$file")")
			if [[ "$from" == "$file" ]]; then
				print_table_row "✓ $name" 60
			elif [[ -n "$from" ]]; then
				print_table_row "○ $name ${GRAY}(launchd loads ${from} instead)${NC}" 60
			else
				print_table_row "○ $name ${GRAY}(not loaded)${NC}" 60
			fi
			((count++)) || true
		done <<< "$user_agents"
		print_table_row "${GRAY}Total: $count items${NC}" 60
	else
		print_table_row "${GRAY}no user launch agents${NC}" 60
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/7] Background Items (registered by apps)...${NC}"
	print_table_header "Label|PID" 60 10
	background=$(_background_items "$known")
	if [[ -n "$background" ]]; then
		while IFS=$'\t' read -r label pid; do
			[[ -n "$label" ]] || continue
			print_table_row "$label|$pid" 60 10
		done <<< "$background"
	else
		print_table_row "${GRAY}none${NC}|" 60 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/7] System LaunchAgents...${NC}"
	print_table_header "Source|Files|Loaded" 30 8 8
	if [[ -n "$sys_agents" ]]; then
		print_table_row "/Library/LaunchAgents/|$(printf '%s\n' "$sys_agents" | grep -c .)|$(printf '%s\n' "$sys_agents" | awk -F'\t' '$3 != ""' | grep -c . || true)" 30 8 8
	else
		print_table_row "${GRAY}none found${NC}|0|0" 30 8 8
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/7] LaunchDaemons...${NC}"
	print_table_header "Source|Count" 30 10
	local daemons
	daemons=$(ls -1 /Library/LaunchDaemons/*.plist 2>/dev/null | wc -l | tr -d ' ')
	if [[ "$daemons" -gt 0 ]]; then
		print_table_row "/Library/LaunchDaemons/|$daemons" 30 10
	else
		print_table_row "${GRAY}none found${NC}|0" 30 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[5/7] Login Items...${NC}"
	print_table_header "Item" 60
	local login_items
	if login_items=$(_login_items 2>&1); then
		if [[ -n "$login_items" ]]; then
			while IFS=$'\t' read -r item path; do
				[[ -n "$item" ]] || continue
				if [[ "$path" == "missing value" ]]; then
					print_table_row "○ $item ${GRAY}(target is gone, nothing opens)${NC}" 60
				else
					print_table_row "✓ $item" 60
				fi
			done <<< "$login_items"
		else
			print_table_row "${GRAY}no login items configured${NC}" 60
		fi
		echo "${GREEN}✓${NC}"
	else
		print_table_row "${YELLOW}not checked${NC}: ${login_items:-System Events did not answer}" 60
		print_warning "Grant Automation access to System Events to list login items"
	fi

	echo ""
	echo "${GRAY}[6/7] Services...${NC}"
	print_table_header "Service|PID" 45 10
	local loaded running
	loaded=$(_launchctl_list | grep -c . || true)
	running=$(_launchctl_list | awk '$1 != "-"' | grep -c . || true)
	print_table_row "Loaded by launchd|$loaded" 45 10
	print_table_row "With a process right now|$running" 45 10
	_launchctl_list | awk '$1 != "-" {print $3 "|" $1}' | head -5 | while IFS='|' read -r svc pid; do
		[[ -n "$svc" ]] && print_table_row "$svc|$pid" 45 10
	done || true
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[7/7] System Uptime...${NC}"
	print_table_header "Metric" 40
	local uptime_str load
	uptime_str=$(uptime 2>/dev/null | sed 's/.*up \(.*\), [0-9]* user.*/\1/' || echo "N/A")
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
