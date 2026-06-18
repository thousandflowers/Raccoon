#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_backup_help() {
	print_help_header "backup" "Check Time Machine backup status" ""
	echo ""
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_backup_help
		exit 0
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
	backup_date=$(basename "$last_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)

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

main() {
	print_section_header "Time Machine"
	check_tm_destination
	check_tm_phase
	check_last_backup
	check_tm_exclusions

	echo ""
	print_success "Completed"
}

main "$@"