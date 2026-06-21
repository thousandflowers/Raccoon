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
	print_table_header "Disk|Int/Ext|Size|Mount|SMART" 10 8 12 20 10

	# ponytail: only physical disks from diskutil list (internal + external)
	local disk_lines disk_line disk_id disk_type disk_info disk_size smart smart_colored
	disk_lines=$(diskutil list 2>/dev/null | grep '(physical)' || true)
	if [[ -n "$disk_lines" ]]; then
		while IFS= read -r disk_line; do
			[[ -z "$disk_line" ]] && continue
			disk_id=$(echo "$disk_line" | sed 's|/dev/||' | awk '{print $1}')
			disk_type=$(echo "$disk_line" | grep -oE '(internal|external)' || true)
			disk_info=$(diskutil info "$disk_id" 2>/dev/null || true)
			disk_size=$(echo "$disk_info" | grep "Disk Size" | head -1 | awk '{print $3, $4}' || true)
			smart=$(echo "$disk_info" | grep "SMART Status" | head -1 | awk '{print $3}' || true)
			# ponytail: mount point from the first volume on this disk
			# We extract from df lines that start with /dev/[disk_id]s
			local mount_found mount_line
			mount_found=""
			mount_line=$(df -h 2>/dev/null | grep "^/dev/${disk_id}s" | head -1 | awk '{print $NF}' || true)
			[[ -n "$mount_line" ]] && mount_found="$mount_line"
			case "$smart" in
				Verified) smart_colored="${GREEN}Verified${NC}" ;;
				Failing) smart_colored="${RED}Failing${NC}" ;;
				*) smart_colored="${GRAY}N/A${NC}" ;;
			esac
			print_table_row "$disk_id|$disk_type|${disk_size:-?}|${mount_found:-${GRAY}none${NC}}|$smart_colored" 10 8 12 20 10
		done <<< "$disk_lines"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/5] Volumes...${NC}"
	print_table_header "Volume|Mount|Type|Used|Free" 22 22 8 10 10

	# ponytail: scan df for all non-network, non-devfs volumes from physical disks
	local vol_count
	vol_count=0
	while IFS= read -r vol_line; do
		[[ -z "$vol_line" ]] && continue
		local vol_dev vol_mount vol_used vol_free
		vol_dev=$(echo "$vol_line" | awk '{print $1}')
		vol_mount=$(echo "$vol_line" | awk '{print $NF}')
		vol_used=$(echo "$vol_line" | awk '{print $3}')
		vol_free=$(echo "$vol_line" | awk '{print $4}')
		local vol_name
		vol_name=$(basename "$vol_mount")
		[[ "$vol_dev" == "map"* ]] && continue
		[[ "$vol_dev" == "devfs" ]] && continue
		# Show only user-relevant volumes: the boot volume (/), the Data volume,
		# and any external mounts. Hide the synthesized helpers that share the
		# APFS container (Preboot, VM, Update, Recovery, xarts, iSCPreboot, …).
		case "$vol_mount" in
			/) vol_name="System" ;;
			/System/Volumes/Data) vol_name="Data" ;;
			/System/Volumes/*) continue ;;
		esac
		print_table_row "$vol_name|$vol_mount|APFS|$vol_used|$vol_free" 22 22 8 10 10
		((vol_count++)) || true
	done < <(df -h 2>/dev/null | grep "^/dev/disk")
	if [[ $vol_count -eq 0 ]]; then
		print_table_row "System|/|APFS|?|?" 22 22 8 10 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/5] APFS Container...${NC}"
	print_table_header "Container|Size|Free" 18 12 12

	local container_info container_ref container_size container_line container_free
	container_info=$(diskutil apfs list 2>/dev/null || true)
	container_ref=$(echo "$container_info" | grep "Container Reference:" | head -1 | awk '{print $NF}' || true)
	container_size=$(echo "$container_info" | grep "Size (Capacity Ceiling):" | head -1 | sed 's/.*(\([0-9.]*\) GB.*/\1 GB/' || true)
	container_line=$(echo "$container_info" | grep "Capacity Not Allocated:" | head -1 || true)
	# shellcheck disable=SC2001
	container_free=$(echo "$container_line" | sed 's/.*(\([0-9.]*\) GB.*/\1 GB/')
	print_table_row "$container_ref|$container_size|$container_free" 18 12 12
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/5] Space Usage...${NC}"
	print_table_header "Mount|Used|Free|Percent" 22 10 10 10

	# ponytail: dynamic scan, same as [2/5] but only user-relevant mounts
	local space_count
	space_count=0
	while IFS= read -r sp_line; do
		[[ -z "$sp_line" ]] && continue
		local sp_mount sp_used sp_free sp_pct
		sp_mount=$(echo "$sp_line" | awk '{print $NF}')
		sp_used=$(echo "$sp_line" | awk '{print $3}')
		sp_free=$(echo "$sp_line" | awk '{print $4}')
		sp_pct=$(echo "$sp_line" | awk '{print $5}')
		# Same filter as [2/5]: hide synthesized helper volumes, keep / + Data.
		case "$sp_mount" in
			/System/Volumes/Data) ;;
			/System/Volumes/*) continue ;;
		esac
		print_table_row "$sp_mount|$sp_used|$sp_free|$sp_pct" 22 10 10 10
		((space_count++)) || true
	done < <(df -h 2>/dev/null | grep "^/dev/disk")
	if [[ $space_count -eq 0 ]]; then
		print_table_row "/|?|?|?" 22 10 10 10
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
