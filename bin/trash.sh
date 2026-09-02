#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_trash_help() {
	echo "Usage: rcc trash [options]"
	echo ""
	echo "Show trash contents and size"
	echo ""
	echo "Options:"
	echo "  --empty        Empty the trash (requires confirmation)"
	echo "  --json        Output in JSON format"
	echo "  --help, -h   Show this help"
}

# shellcheck disable=SC2034
	JSON_OUTPUT=false
# shellcheck disable=SC2034
EMPTY_TRASH=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_trash_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	--empty)
		EMPTY_TRASH=true
		;;
	*)
		;;
	esac
done

# The trash of every mounted volume that has one.
#
# macOS gives each volume its own `.Trashes/<uid>`: delete a file on an
# external disk and it goes there, not to ~/.Trash. A report that reads only
# the home one tells someone their trash is empty while a hundred gigabytes
# sit on the drive they just unplugged.
#
# The boot volume is skipped — its trash is ~/.Trash, already counted — and so
# is the synthetic snapshot mount, which is not a volume anyone puts files on.
# The root is a parameter so a test can point it somewhere it may write:
# /Volumes needs root, and a check that skips itself proves nothing.
_trash_volume_dirs() {
	local root="${1:-/Volumes}" vol uid
	uid=$(id -u)
	for vol in "$root"/*; do
		[[ -d "$vol" ]] || continue
		case "$(basename "$vol")" in
			com.apple.TimeMachine.*) continue ;;
		esac
		# The boot volume appears here as a symlink to /.
		[[ "$(readlink "$vol" 2>/dev/null)" == "/" ]] && continue
		[[ -d "$vol/.Trashes/$uid" ]] || continue
		printf '%s\n' "$vol/.Trashes/$uid"
	done
}

# Size and item count of one trash directory, as `size<TAB>count`.
_trash_measure() {
	local dir="$1" size count
	size=$( { du -sh "$dir" 2>/dev/null || true; } | awk '{print $1}')
	[[ -z "$size" ]] && size="0"
	count=$( { find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null || true; } | wc -l | tr -dc '0-9')
	[[ -z "$count" ]] && count="0"
	printf '%s\t%s' "$size" "$count"
}

main() {
	local trash_path="$HOME/.Trash"

	# JSON is a clean machine-readable fast-path: emit only the object, no tables.
	if [[ "$JSON_OUTPUT" == "true" ]]; then
		local size="0" count="0" measured
		if [[ -d "$trash_path" ]]; then
			# Absorb a failing find/du INSIDE the pipe (|| true) — a trailing
			# `|| echo 0` would concatenate onto wc's "0" and break the JSON.
			measured=$(_trash_measure "$trash_path")
			size=${measured%%$'\t'*}
			count=${measured##*$'\t'}
		fi
		# rcc_json_string, not a bare %s: a volume named  O'Brien's disk  would
		# otherwise close the string early and hand the reader a broken document.
		printf '{"path":%s,"size":%s,"count":%s,\n' \
			"$(rcc_json_string "$trash_path")" \
			"$(rcc_json_string "$size")" \
			"$(rcc_json_number "$count")"
		printf ' "volumes":['
		local vdir vmeasured vfirst=1
		while IFS= read -r vdir; do
			[[ -z "$vdir" ]] && continue
			vmeasured=$(_trash_measure "$vdir")
			[[ $vfirst -eq 1 ]] || printf ','
			vfirst=0
			printf '\n   {"path":%s,"size":%s,"count":%s}' \
				"$(rcc_json_string "$vdir")" \
				"$(rcc_json_string "${vmeasured%%$'\t'*}")" \
				"$(rcc_json_number "${vmeasured##*$'\t'}")"
		done < <(_trash_volume_dirs "${RCC_VOLUMES_ROOT:-/Volumes}")
		[[ $vfirst -eq 1 ]] || printf '\n '
		printf ']}\n'
		return 0
	fi

	print_section_header "Trash Status"

	echo "${GRAY}[1/3] Trash Location...${NC}"
	print_table_header "Setting|Value" 20 30
	print_table_row "Path|$trash_path" 20 30
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/3] Trash Contents...${NC}"

	if [[ ! -d "$trash_path" ]]; then
		print_table_row "Status|${GRAY}Trash folder not found${NC}" 20 30
		echo "${GREEN}✓${NC}"
		echo ""
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	local size count
	size=$(du -sh "$trash_path" 2>/dev/null | awk '{print $1}' || echo "0")
	count=$(find "$trash_path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | xargs || echo "0")

	print_table_row "Size|$size" 20 30
	print_table_row "Items|$count files/folders" 20 30

	if [[ -n "$size" && "$size" != "0" ]]; then
		local size_num
		size_num="${size//[A-Za-z]/}"
		local unit
		unit="${size//[0-9.]/}"

		if [[ "$unit" == *"G"* ]] && (( $(echo "$size_num > 1" | bc -l) )); then
			print_table_row "Warning|${YELLOW}Trash contains large files${NC}" 20 30
		fi
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/3] Recent Items (Last 10)...${NC}"
	print_table_header "Item" 40

	# shellcheck disable=SC2012
	ls -lt "$trash_path" 2>/dev/null | head -11 | tail -n +2 | while read -r line; do
		# shellcheck disable=SC2034
		local item_date='' item_name
		item_name=$(echo "$line" | awk '{for(i=9;i<=NF;i++) printf "%s%s",$i,(i<NF?" ":"")}')
		[[ -n "$item_name" ]] && print_table_row "$item_name" 40
	done || print_table_row "${GRAY}empty${NC}" 40

	echo "${GREEN}✓${NC}"

	if [[ "$EMPTY_TRASH" == "true" ]]; then
		echo ""
		local answer="n"
		if [[ -z "${RACCOON_TEST:-}" ]]; then
			echo -n "Empty the trash? [y/N] "
			read -r answer || answer="n"   # don't abort under set -e on EOF (pipe/TUI)
		fi
		if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
			osascript -e 'tell application "Finder" to empty trash' 2>/dev/null || rm -rf "${trash_path:?}"/*
			echo "${GREEN}✓ Trash emptied${NC}"
		fi
	fi

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"