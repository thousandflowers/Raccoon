#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_backup_help() {
	echo "Usage: rcc backup [options]"
	echo ""
	echo "Check Time Machine backup status"
	echo ""
	echo "Options:"
	echo "  --help, -h      Show this help"
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_backup_help
		exit 0
		;;
	*)
		echo "Unknown option: $arg"
		echo "Usage: rcc backup"
		exit 1
		;;
	esac
done

main() {
	print_section_header "Time Machine Backup"

	# Check if TM is configured
	local dest
	dest=$(tmutil destinationinfo 2>/dev/null | grep "Name:" | head -1 |
		cut -d: -f2- | xargs 2>/dev/null || echo "")

	if [[ -z "$dest" ]]; then
		echo -e "  ${RED}${ICON_ERROR} Time Machine not configured${NC}"
		echo ""
		echo "  Configure in: System Settings > General > Time Machine"
		return 0
	fi

	echo -e "  Destination:  ${GREEN}${dest}${NC}"

	# Last backup
	local last_backup
	last_backup=$(tmutil latestbackup 2>/dev/null || echo "")

	if [[ -z "$last_backup" ]]; then
		echo -e "  Last Backup:  ${YELLOW}No backup found${NC}"
		return 0
	fi

	# Extract date from path (format: .../YYYY-MM-DD-HHMMSS)
	local backup_date
	backup_date=$(basename "$last_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)

	local now
	now=$(date +%s)
	local backup_ts
	backup_ts=$(date -j -f "%Y-%m-%d" "$backup_date" +%s 2>/dev/null || echo "0")
	local diff=$(((now - backup_ts) / 3600))

	if [[ $diff -lt 24 ]]; then
		echo -e "  Last Backup:  ${GREEN}${backup_date} (${diff}h ago)${NC}"
	elif [[ $diff -lt 168 ]]; then
		echo -e "  Last Backup:  ${YELLOW}${backup_date} (${diff}h ago)${NC}"
	else
		echo -e "  Last Backup:  ${RED}${backup_date} (${diff}h ago — overdue!)${NC}"
	fi

	echo ""
}

main "$@"
