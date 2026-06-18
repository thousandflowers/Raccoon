#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_disk_help() {
	echo "Usage: rcc disk [options]"
	echo ""
	echo "Show disk status — internal, external, and network volumes"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

# shellcheck disable=SC2034
	JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_disk_help
		exit 0
		;;
	--json)
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Disk Status"

	echo "${GRAY}[1/5] Physical Disks...${NC}"
	print_table_header "Disk|Int/Ext|Size|SMART" 10 8 12 10

	# ponytail: only physical disks from diskutil list (internal + external)
	local disk_lines disk_line disk_id disk_type disk_info disk_size smart smart_colored
	disk_lines=$(diskutil list 2>/dev/null | grep '(physical)')
	if [[ -n "$disk_lines" ]]; then
		while IFS= read -r disk_line; do
			[[ -z "$disk_line" ]] && continue
			disk_id=$(echo "$disk_line" | sed 's|/dev/||' | awk '{print $1}')
			disk_type=$(echo "$disk_line" | grep -oE '(internal|external)')
			disk_info=$(diskutil info "$disk_id" 2>/dev/null)
			disk_size=$(echo "$disk_info" | grep "Disk Size" | head -1 | awk '{print $3, $4}')
			smart=$(echo "$disk_info" | grep "SMART Status" | head -1 | awk '{print $3}')
			case "$smart" in
				Verified) smart_colored="${GREEN}Verified${NC}" ;;
				Failing) smart_colored="${RED}Failing${NC}" ;;
				*) smart_colored="${GRAY}N/A${NC}" ;;
			esac
			print_table_row "$disk_id|$disk_type|${disk_size:-?}|$smart_colored" 10 8 12 10
		done <<< "$disk_lines"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/5] Volumes...${NC}"
	print_table_header "Volume|Type|Used|Free" 18 8 10 10

	root_info=$(df -h / | tail -1)
	root_used=$(echo "$root_info" | awk '{print $3}')
	root_free=$(echo "$root_info" | awk '{print $4}')
	root_pct=$(echo "$root_info" | awk '{print $5}')
	print_table_row "System|APFS|$root_used|$root_free" 18 8 10 10

	data_info=$(df -h /System/Volumes/Data 2>/dev/null | tail -1 || echo "")
	if [[ -n "$data_info" ]]; then
		data_used=$(echo "$data_info" | awk '{print $3}')
		data_free=$(echo "$data_info" | awk '{print $4}')
		data_pct=$(echo "$data_info" | awk '{print $5}')
		print_table_row "Data|APFS|$data_used|$data_free" 18 8 10 10
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/5] APFS Container...${NC}"
	print_table_header "Container|Size|Free" 18 12 12

	container_info=$(diskutil apfs list 2>/dev/null)
	container_ref=$(echo "$container_info" | grep "Container Reference:" | head -1 | awk '{print $NF}')
	container_size=$(echo "$container_info" | grep "Size (Capacity Ceiling):" | head -1 | sed 's/.*(\([0-9.]*\) GB.*/\1 GB/')
	container_line=$(echo "$container_info" | grep "Capacity Not Allocated:" | head -1)
	# shellcheck disable=SC2001
	container_free=$(echo "$container_line" | sed 's/.*(\([0-9.]*\) GB.*/\1 GB/')
	print_table_row "$container_ref|$container_size|$container_free" 18 12 12
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/5] Space Usage...${NC}"
	print_table_header "Volume|Used|Free|Percent" 18 8 10 10

	print_table_row "System|$root_used|$root_free|$root_pct" 18 8 10 10
	if [[ -n "${data_used:-}" ]]; then
		print_table_row "Data|$data_used|$data_free|$data_pct" 18 8 10 10
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[5/5] Network Mounts...${NC}"
	# ponytail: df -t with network filesystem types; no output = no network mounts
	local net_output
	net_output=$(df -h -t smbfs,nfs,afpfs 2>/dev/null | tail -n +2)
	if [[ -z "$net_output" ]]; then
		echo "  ${GRAY}No network mounts${NC}"
	else
		print_table_header "Mount|Size|Used|Free" 25 10 10 10
		while IFS= read -r line; do
			[[ -z "$line" ]] && continue
			print_table_row "$(echo "$line" | awk '{print $NF}')|$(echo "$line" | awk '{print $2}')|$(echo "$line" | awk '{print $3}')|$(echo "$line" | awk '{print $4}')" 25 10 10 10
		done <<< "$net_output"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
