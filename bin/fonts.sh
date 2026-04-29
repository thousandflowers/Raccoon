#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_fonts_help() {
	echo "Usage: rcc fonts [options]"
	echo ""
	echo "Show installed fonts and check for duplicates"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_fonts_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Fonts Status"

	echo "${GRAY}[1/4] System Fonts...${NC}"
	print_table_header "Source|Count" 25 20

	local sys_fonts
	sys_fonts=$(ls -1 /Library/Fonts/ 2>/dev/null | wc -l | xargs || echo "0")
	print_table_row "/Library/Fonts/|$sys_fonts" 25 20

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] User Fonts...${NC}"
	print_table_header "Source|Count" 25 20

	local user_fonts
	user_fonts=$(ls -1 ~/Library/Fonts/ 2>/dev/null | wc -l | xargs || echo "0")
	print_table_row "~/Library/Fonts/|$user_fonts" 25 20

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] FontConfig Catalog...${NC}"

	print_table_header "Metric|Count" 25 20

	if command -v fc-list >/dev/null 2>&1; then
		local fc_count fc_families
		fc_count=$(fc-list : family 2>/dev/null | wc -l | xargs || echo "0")
		fc_families=$(fc-list : family 2>/dev/null | sort -u | wc -l | xargs || echo "0")
		print_table_row "Total fonts|$fc_count" 25 20
		print_table_row "Unique families|$fc_families" 25 20
	else
		print_table_row "fontconfig|${YELLOW}not installed${NC}" 25 20
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Duplicate & Corrupt Check...${NC}"

	print_table_header "Check|Result" 25 20

	if command -v fc-list >/dev/null 2>&1; then
		local duplicates
		duplicates=$(fc-list : family 2>/dev/null | sort | uniq -d | wc -l | xargs || echo "0")
		if [[ "$duplicates" -gt 0 ]]; then
			print_table_row "Duplicates|${YELLOW}${duplicates} families${NC}" 25 20
		else
			print_table_row "Duplicates|${GREEN}none found${NC}" 25 20
		fi

		local corrupted=0
		local all_fonts
		all_fonts=$(ls /Library/Fonts/*.{ttf,otf} ~/Library/Fonts/*.{ttf,otf} 2>/dev/null || true)
		for font in $all_fonts; do
			[[ ! -f "$font" ]] && continue
			fc-scan "$font" >/dev/null 2>&1 || ((corrupted++))
		done 2>/dev/null || true
		print_table_row "Corrupted fonts|$corrupted" 25 20
	else
		print_table_row "Checks|${GRAY}skipped${NC}" 25 20
	fi

	local total=$((sys_fonts + user_fonts))
	print_table_row "${GRAY}Total installed${NC}|$total fonts" 25 20

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"