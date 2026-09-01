#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_backup_help() {
	print_help_header "backup" "Check Time Machine backup status" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_backup_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

check_tm_destination() {
	local dest kind
	dest=$(tmutil destinationinfo 2>/dev/null | grep "Name:" | head -1 |
		cut -d: -f2- | xargs 2>/dev/null || echo "")
	kind=$(tmutil destinationinfo 2>/dev/null | grep "Kind:" | head -1 | cut -d: -f2- | xargs || echo "")

	# ponytail: plain-text parse fails during backups (field absent).
	# fallback: XML parse via Perl one-liner.
	if [[ -z "$dest" ]]; then
		local xml_dest
		xml_dest=$(tmutil destinationinfo -X 2>/dev/null | perl -wne 'print $1 if /<key>Name<\/key>\s*<string>(.*?)<\/string>/s' 2>/dev/null || echo "")
		[[ -n "$xml_dest" ]] && dest="$xml_dest"
	fi

	print_table_header "Setting|Value" 20 30

	if [[ -z "$dest" ]]; then
		print_table_row "Destination|${RED}Not configured${NC}" 20 30
		return 0
	fi

	print_table_row "Destination|${GREEN}${dest}${NC}" 20 30
	[[ -n "$kind" ]] && print_table_row "Kind|$kind" 20 30
}

check_tm_phase() {
	local phase
	phase=$(tmutil currentphase 2>/dev/null || echo "unknown")
	case "$phase" in
		BackupNotRunning) phase="${GREEN}Idle${NC}" ;;
		BackupRunning) phase="${YELLOW}Backing up...${NC}" ;;
		*) phase="${GRAY}$phase${NC}" ;;
	esac
	print_table_row "Status|$phase" 20 30
}

check_last_backup() {
	local last_backup
	last_backup=$(tmutil latestbackup 2>/dev/null || echo "")

	print_table_header "Last Backup|When" 20 30

	if [[ -z "$last_backup" ]]; then
		print_table_row "Backup|${YELLOW}No backup found${NC}" 20 30
		return 0
	fi

	local backup_date
	backup_date=$(basename "$last_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")

	local now
	now=$(date +%s)
	local backup_ts
	backup_ts=$(date -j -f "%Y-%m-%d" "$backup_date" +%s 2>/dev/null || echo "0")
	local diff=$(((now - backup_ts) / 3600))

	if [[ $diff -lt 24 ]]; then
		print_table_row "Backup|${GREEN}${backup_date} (${diff}h ago)${NC}" 20 30
	elif [[ $diff -lt 168 ]]; then
		print_table_row "Backup|${YELLOW}${backup_date} (${diff}h ago)${NC}" 20 30
	else
		print_table_row "Backup|${RED}${backup_date} (${diff}h overdue!)${NC}" 20 30
	fi
}

check_tm_exclusions() {
	local excl_count=0
	if mdfind "kMDItemFSLabel = 6" 2>/dev/null | head -1 | grep -q .; then
		echo ""
		echo "${GRAY}Exclusions (Spotlight-tagged)...${NC}"
		while IFS= read -r excl_path; do
			[[ -z "$excl_path" ]] && continue
			echo "  ${GRAY}$excl_path${NC}"
			((excl_count++)) || true
		done < <(mdfind "kMDItemFSLabel = 6" 2>/dev/null | head -10)
	else
		# ponytail: mdfind returns nothing when no exclusions; no news is good news
		:
	fi
}

# Hours since the last backup, or -1 when there has never been one. The number
# is what decides whether this is fine, late, or a problem: a date on its own
# needs the reader to do the arithmetic.
_backup_age_hours() {
	local latest date_ ts now
	latest=$(tmutil latestbackup 2>/dev/null || printf '')
	[[ -n "$latest" ]] || { printf -- '-1'; return 0; }
	date_=$(basename "$latest" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || printf '')
	[[ -n "$date_" ]] || { printf -- '-1'; return 0; }
	ts=$(date -j -f "%Y-%m-%d" "$date_" +%s 2>/dev/null || printf '0')
	[[ "$ts" != "0" ]] || { printf -- '-1'; return 0; }
	now=$(date +%s)
	printf '%s' "$(((now - ts) / 3600))"
}

_json_report() {
	local dest kind phase latest date_ hours first path
	dest=$(tmutil destinationinfo 2>/dev/null | grep "Name:" | head -1 | cut -d: -f2- | xargs || printf '')
	if [[ -z "$dest" ]]; then
		dest=$(tmutil destinationinfo -X 2>/dev/null | perl -wne 'print $1 if /<key>Name<\/key>\s*<string>(.*?)<\/string>/s' 2>/dev/null || printf '')
	fi
	kind=$(tmutil destinationinfo 2>/dev/null | grep "Kind:" | head -1 | cut -d: -f2- | xargs || printf '')
	phase=$(tmutil currentphase 2>/dev/null || printf 'unknown')
	latest=$(tmutil latestbackup 2>/dev/null || printf '')
	date_=$(basename "${latest:-}" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || printf '')
	hours=$(_backup_age_hours)

	printf '{\n'
	printf '  "destination": {"configured": %s, "name": %s, "kind": %s},\n' \
		"$([[ -n "$dest" ]] && echo true || echo false)" \
		"$(rcc_json_string "$dest")" "$(rcc_json_string "$kind")"
	printf '  "phase": %s,\n' "$(rcc_json_string "$phase")"
	printf '  "running": %s,\n' "$([[ "$phase" != "BackupNotRunning" && "$phase" != "unknown" ]] && echo true || echo false)"
	printf '  "last_backup": {"date": %s, "hours_ago": %s},\n' \
		"$(rcc_json_string "$date_")" "$hours"

	printf '  "exclusions": ['
	first=1
	while IFS= read -r path; do
		[[ -z "$path" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$path")"
	done < <(mdfind "kMDItemFSLabel = 6" 2>/dev/null | head -10 || true)
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	print_section_header "Time Machine"
	check_tm_destination
	check_tm_phase
	check_last_backup
	check_tm_exclusions

	echo ""
	print_success "Completed"
}

main "$@"