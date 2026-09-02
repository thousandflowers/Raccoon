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
	echo "  --large [PATH]      Find the biggest files (default PATH: \$HOME)"
	echo "    --min SIZE        Minimum file size (default: 100M)"
	echo "    --top N           How many to show (default: 20)"
	echo "  --json              Output in JSON format"
	echo "  --help, -h          Show this help"
	echo ""
	echo "Examples:"
	echo "  rcc disk --large"
	echo "  rcc disk --large ~/Downloads"
	echo "  rcc disk --large --min 500M --top 10"
}

# shellcheck disable=SC2034
JSON_OUTPUT=false
LARGE_MODE=false
SEARCH_PATH="$HOME"
MIN_SIZE="100M"
TOP_N=20

while [[ $# -gt 0 ]]; do
	case "$1" in
	--help | -h)
		show_disk_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		shift
		;;
	--large)
		LARGE_MODE=true
		shift
		# Optional positional PATH (anything that is not another flag).
		if [[ $# -gt 0 && "$1" != -* ]]; then
			SEARCH_PATH="$1"
			shift
		fi
		;;
	--min)
		if [[ $# -ge 2 ]]; then MIN_SIZE="$2"; shift 2; else shift; fi
		;;
	--top)
		if [[ $# -ge 2 ]]; then TOP_N="$2"; shift 2; else shift; fi
		;;
	*)
		shift
		;;
	esac
done

# Find the biggest files under SEARCH_PATH. Uses find -exec du so du never runs
# on an empty input (which would report the cwd), and skips dotfiles and caches.
show_large_files() {
	print_section_header "Large Files"
	echo "${GRAY}Searching $SEARCH_PATH for files larger than $MIN_SIZE...${NC}"
	print_table_header "Size|Path" 10 64
	local found size path
	found="$(find "$SEARCH_PATH" -maxdepth 6 -type f -size +"$MIN_SIZE" \
		-not -path "*/.*" \
		-not -path "*/Library/Caches/*" \
		-exec du -sh {} + 2>/dev/null | sort -rh | head -n "$TOP_N" || true)"
	if [[ -n "$found" ]]; then
		while IFS=$'\t' read -r size path; do
			[[ -z "$size" ]] && continue
			print_table_row "$size|$path" 10 64
		done <<< "$found"
	else
		print_table_row "${GRAY}No files over $MIN_SIZE found${NC}" 10 64
	fi
	echo "${GRAY}Cerca con: find $SEARCH_PATH -size +$MIN_SIZE${NC}"
}

# The synthesized helper volumes an APFS container carries: Preboot, VM,
# Update, Recovery. Nobody manages their space, and they bury the two mounts
# that matter.
# Local APFS snapshots, and where to ask for them.
#
# Mole reported two dozen of these on a Mac where `rcc disk` showed none: there
# was no code here that looked. They matter more than their obscurity suggests
# — a snapshot holds on to blocks belonging to files already deleted, so a disk
# reports free space it will not hand over, which is the whole shape of "I
# emptied the Trash and nothing changed".
#
# Ask the Data volume by name. `diskutil apfs listSnapshots /` answers for the
# sealed System volume and finds the one OS-update snapshot, so a report built
# on it says 1 where the truth is 24. Neither call needs sudo, and a read-only
# disk report must never raise a Touch ID prompt.
# Whether this machine can be asked at all. Without diskutil — /usr/sbin off
# the PATH, a trimmed environment — the honest answer is "not checked", never
# "none": reporting zero snapshots to someone whose disk is full of them is
# the same defect as reporting a wrong count.
_disk_can_read_snapshots() {
	command -v diskutil >/dev/null 2>&1
}

_disk_snapshot_names() {
	diskutil apfs listSnapshots /System/Volumes/Data 2>/dev/null \
		| sed -n 's/^[[:space:]|+-]*Name:[[:space:]]*//p' || true
}

# How many of them macOS says it can reclaim. `Purgeable: No` is an OS-update
# snapshot that cannot be deleted, and counting it as recoverable would promise
# space that is not there.
_disk_snapshots_purgeable() {
	diskutil apfs listSnapshots /System/Volumes/Data 2>/dev/null \
		| grep -c 'Purgeable:[[:space:]]*Yes' || true
}

_disk_is_helper() {
	case "$1" in
		/System/Volumes/Data) return 1 ;;
		/System/Volumes/*) return 0 ;;
		*) return 1 ;;
	esac
}

_json_report() {
	local line id type_ info size smart mount first
	printf '{\n'

	printf '  "disks": ['
	first=1
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		id=$(printf '%s' "$line" | sed 's|/dev/||' | awk '{print $1}')
		type_=$(printf '%s' "$line" | grep -oE '(internal|external)' || printf '')
		info=$(diskutil info "$id" 2>/dev/null || printf '')
		size=$(printf '%s' "$info" | grep "Disk Size" | head -1 | awk '{print $3, $4}' || printf '')
		smart=$(printf '%s' "$info" | grep "SMART Status" | head -1 | awk '{print $3}' || printf '')
		mount=$(df -h 2>/dev/null | grep "^/dev/${id}s" | head -1 | awk '{print $NF}' || printf '')
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"id": %s, "type": %s, "size": %s, "mount": %s, "smart": %s}' \
			"$(rcc_json_string "$id")" "$(rcc_json_string "$type_")" \
			"$(rcc_json_string "$size")" "$(rcc_json_string "$mount")" \
			"$(rcc_json_string "${smart:-Not supported}")"
	done < <(diskutil list 2>/dev/null | grep 'physical)' || true)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	# One list, not two: the text report shows these mounts twice, once with
	# used and free and once with the percentage.
	printf '  "volumes": ['
	first=1
	local vol_mount vol_used vol_free vol_pct vol_name
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		vol_mount=$(printf '%s' "$line" | awk '{print $NF}')
		_disk_is_helper "$vol_mount" && continue
		vol_used=$(printf '%s' "$line" | awk '{print $3}')
		vol_free=$(printf '%s' "$line" | awk '{print $4}')
		vol_pct=$(printf '%s' "$line" | awk '{print $5}')
		case "$vol_mount" in
			/) vol_name="System" ;;
			/System/Volumes/Data) vol_name="Data" ;;
			*) vol_name=$(basename "$vol_mount") ;;
		esac
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "mount": %s, "used": %s, "free": %s, "percent": %s}' \
			"$(rcc_json_string "$vol_name")" "$(rcc_json_string "$vol_mount")" \
			"$(rcc_json_string "$vol_used")" "$(rcc_json_string "$vol_free")" \
			"$(rcc_json_string "$vol_pct")"
	done < <(df -h 2>/dev/null | grep "^/dev/disk" || true)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	local cinfo cref csize cfree
	cinfo=$(diskutil apfs list 2>/dev/null || printf '')
	cref=$(printf '%s' "$cinfo" | grep "Container Reference:" | head -1 | awk '{print $NF}' || printf '')
	csize=$(printf '%s' "$cinfo" | grep "Size (Capacity Ceiling):" | head -1 | sed 's/.*(\([0-9.]*\) GB.*/\1 GB/' || printf '')
	cfree=$(printf '%s' "$cinfo" | grep "Capacity Not Allocated:" | head -1 | sed 's/.*(\([0-9.]*\) GB.*/\1 GB/' || printf '')
	printf '  "apfs_container": {"reference": %s, "size": %s, "free": %s},\n' \
		"$(rcc_json_string "$cref")" "$(rcc_json_string "$csize")" "$(rcc_json_string "$cfree")"

	# Counts through rcc_json_number: every one comes out of a pipeline that
	# can produce nothing, and an empty string here writes `"count": ,` into a
	# document no reader can open.
	local snap_names snap_count snap_purge snap_oldest
	snap_names="$(_disk_snapshot_names)"
	snap_count=$(printf '%s' "$snap_names" | grep -c . || true)
	snap_purge="$(_disk_snapshots_purgeable)"
	snap_oldest=$(printf '%s\n' "$snap_names" \
		| grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | sort | head -1 || true)
	local snap_ok="false"
	_disk_can_read_snapshots && snap_ok="true"
	printf '  "snapshots": {"available": %s, "count": %s, "reclaimable": %s, "oldest": %s},\n' \
		"$snap_ok" \
		"$(rcc_json_number "$snap_count")" \
		"$(rcc_json_number "$snap_purge")" \
		"$(rcc_json_string "$snap_oldest")"

	printf '  "network_mounts": ['
	first=1
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"source": %s, "mount": %s}' \
			"$(rcc_json_string "$(printf '%s' "$line" | awk '{print $1}')")" \
			"$(rcc_json_string "$(printf '%s' "$line" | awk '{print $NF}')")"
	done < <(df -h -t smbfs,nfs,afpfs 2>/dev/null | tail -n +2 || true)
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	if [[ "$LARGE_MODE" == "true" ]]; then
		show_large_files
		return 0
	fi

	print_section_header "Disk Status"

	echo "${GRAY}[1/6] Physical Disks...${NC}"
	print_table_header "Disk|Int/Ext|Size|Mount|SMART" 10 8 12 20 10

	# ponytail: only physical disks from diskutil list (internal + external)
	local disk_lines disk_line disk_id disk_type disk_info disk_size smart smart_colored
	# diskutil prints "(internal, physical):" / "(external, physical):" — never a bare "(physical)"
	disk_lines=$(diskutil list 2>/dev/null | grep 'physical)' || true)
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
	echo "${GRAY}[2/6] Volumes...${NC}"
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
	echo "${GRAY}[3/6] APFS Container...${NC}"
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
	echo "${GRAY}[4/6] Local Snapshots...${NC}"
	local snap_names snap_count snap_purge snap_oldest
	snap_names="$(_disk_snapshot_names)"
	snap_count=$(printf '%s' "$snap_names" | grep -c . || true)
	if ! _disk_can_read_snapshots; then
		echo "  ${YELLOW}Not checked${NC} ${GRAY}(diskutil is not on PATH)${NC}"
	elif [[ "$snap_count" -eq 0 ]]; then
		echo "  ${GRAY}No local snapshots${NC}"
	else
		snap_purge="$(_disk_snapshots_purgeable)"
		# The oldest is the one that matters: it sets how far back deleted
		# blocks are still being held.
		snap_oldest=$(printf '%s\n' "$snap_names" \
			| grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | sort | head -1 || true)
		print_table_header "Snapshots|Reclaimable|Oldest" 12 12 20
		print_table_row "$snap_count|$snap_purge|${snap_oldest:-unknown}" 12 12 20
		echo "  ${GRAY}These hold blocks from deleted files. Free them with:${NC}"
		echo "  ${GRAY}tmutil deletelocalsnapshots /${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[5/6] Space Usage...${NC}"
	print_table_header "Mount|Used|Free|Percent" 22 10 10 10

	# ponytail: dynamic scan, same as [2/6] but only user-relevant mounts
	local space_count
	space_count=0
	while IFS= read -r sp_line; do
		[[ -z "$sp_line" ]] && continue
		local sp_mount sp_used sp_free sp_pct
		sp_mount=$(echo "$sp_line" | awk '{print $NF}')
		sp_used=$(echo "$sp_line" | awk '{print $3}')
		sp_free=$(echo "$sp_line" | awk '{print $4}')
		sp_pct=$(echo "$sp_line" | awk '{print $5}')
		# Same filter as [2/6]: hide synthesized helper volumes, keep / + Data.
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
	echo "${GRAY}[6/6] Network Mounts...${NC}"
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
