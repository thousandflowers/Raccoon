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
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
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
	echo "  Path: $trash_path"
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/3] Trash Contents...${NC}"
	
	if [[ ! -d "$trash_path" ]]; then
		echo "  ${GRAY}Trash folder not found${NC}"
		echo "${GREEN}✓${NC}"
		echo ""
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	local size count
	size=$(du -sh "$trash_path" 2>/dev/null | awk '{print $1}' || echo "0")
	count=$(ls -1 "$trash_path" 2>/dev/null | wc -l | xargs || echo "0")

	printf "  Size:  %s\n" "$size"
	printf "  Items: %s files/folders\n" "$count"

	if [[ -n "$size" && "$size" != "0" ]]; then
		local size_num
		size_num=$(echo "$size" | sed 's/[A-Za-z]//g')
		local unit
		unit=$(echo "$size" | sed 's/[0-9.]//g')
		
		if [[ "$unit" == *"G"* ]] && (( $(echo "$size_num > 1" | bc -l) )); then
			echo "  ${YELLOW}Warning: Trash contains large files${NC}"
		fi
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/3] Recent Items (Last 10)...${NC}"
	ls -lt "$trash_path" 2>/dev/null | head -11 | tail -n +2 | while read -r line; do
		local item_date item_name
		item_date=$(echo "$line" | awk '{print $6, $7, $8}')
		item_name=$(echo "$line" | awk '{print $NF}')
		[[ -n "$item_name" ]] && echo "  $item_date  $item_name"
	done || echo "  ${GRAY}empty${NC}"
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"