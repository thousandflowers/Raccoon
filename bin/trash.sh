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

JSON_OUTPUT=false
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

main() {
	print_section_header "Trash Status"

	local trash_path="$HOME/.Trash"

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
	count=$(ls -1 "$trash_path" 2>/dev/null | wc -l | xargs || echo "0")

	print_table_row "Size|$size" 20 30
	print_table_row "Items|$count files/folders" 20 30

	if [[ -n "$size" && "$size" != "0" ]]; then
		local size_num
		size_num=$(echo "$size" | sed 's/[A-Za-z]//g')
		local unit
		unit=$(echo "$size" | sed 's/[0-9.]//g')

		if [[ "$unit" == *"G"* ]] && (( $(echo "$size_num > 1" | bc -l) )); then
			print_table_row "Warning|${YELLOW}Trash contains large files${NC}" 20 30
		fi
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/3] Recent Items (Last 10)...${NC}"
	print_table_header "Item" 40

	ls -lt "$trash_path" 2>/dev/null | head -11 | tail -n +2 | while read -r line; do
		local item_date item_name
		item_date=$(echo "$line" | awk '{print $6, $7, $8}')
		item_name=$(echo "$line" | awk '{print $NF}')
		[[ -n "$item_name" ]] && print_table_row "$item_name" 40
	done || print_table_row "${GRAY}empty${NC}" 40

	echo "${GREEN}✓${NC}"

	if [[ "$EMPTY_TRASH" == "true" ]]; then
		echo ""
		echo -n "Empty the trash? [y/N] "
		read -r answer
		if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
			osascript -e 'tell application "Finder" to empty trash' 2>/dev/null || rm -rf "$trash_path"/*
			echo "${GREEN}✓ Trash emptied${NC}"
		fi
	fi

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"