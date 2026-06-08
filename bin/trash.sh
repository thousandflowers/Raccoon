#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_trash_help() {
	print_help_header "trash" "Show trash contents and size" "[--empty] [--json]"
	echo "  --empty         Empty the trash (requires confirmation)"
	echo "  --json          Output in JSON format"
	echo ""
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
		;;
	--empty)
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Trash Status"

	local trash_path="$HOME/.Trash"

	print_table_header "Setting|Value" 20 30
	print_table_row "Path|$trash_path" 20 30
	print_success "Trash path set"

	echo ""
	print_step 2 3 "Trash Contents"

	if [[ ! -d "$trash_path" ]]; then
		print_table_row "Status|${GRAY}Trash folder not found${NC}" 20 30
		print_success "Trash folder checked"
		echo ""
		print_success "Completed"
		return 0
	fi

	local size count
	size=$(du -sh "$trash_path" 2>/dev/null | awk '{print $1}' || echo "0")
	count=$(find "$trash_path" -maxdepth 1 2>/dev/null | wc -l | xargs || echo "0")

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

	print_success "Trash contents scanned"

	echo ""
	print_step 3 3 "Recent Items (Last 10)"
	print_table_header "Item" 40

	# shellcheck disable=SC2012
	ls -lt "$trash_path" 2>/dev/null | head -11 | tail -n +2 | while read -r line; do
		# shellcheck disable=SC2034
		local item_date='' item_name
		item_name=$(echo "$line" | awk '{print $NF}')
		[[ -n "$item_name" ]] && print_table_row "$item_name" 40
	done || print_table_row "${GRAY}empty${NC}" 40

	print_success "Recent items listed"

	echo ""
	print_success "Completed"
}

main "$@"