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
	local sys_fonts
	sys_fonts=$(ls -1 /Library/Fonts/ 2>/dev/null | wc -l | xargs || echo "0")
	printf "  /Library/Fonts/: %s fonts\n" "$sys_fonts"
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] User Fonts...${NC}"
	local user_fonts
	user_fonts=$(ls -1 ~/Library/Fonts/ 2>/dev/null | wc -l | xargs || echo "0")
	printf "  ~/Library/Fonts/: %s fonts\n" "$user_fonts"
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] FontConfig Catalog...${NC}"
	local fc_count fc_families
	if command -v fc-list >/dev/null 2>&1; then
		fc_count=$(fc-list : family 2>/dev/null | wc -l | xargs || echo "0")
		fc_families=$(fc-list : family 2>/dev/null | sort -u | wc -l | xargs || echo "0")
		printf "  Total fonts:       %s\n" "$fc_count"
		printf "  Unique families: %s\n" "$fc_families"
	else
		echo "  ${GRAY}fontconfig not installed (brew install fontconfig)${NC}"
		fc_count="N/A"
		fc_families="N/A"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Duplicate Check...${NC}"
	if command -v fc-list >/dev/null 2>&1; then
		local duplicates
		duplicates=$(fc-list : family 2>/dev/null | sort | uniq -d | wc -l | xargs || echo "0")
		if [[ "$duplicates" -gt 0 ]]; then
			echo "  ${YELLOW}Found $duplicates duplicate families${NC}"
			fc-list : family 2>/dev/null | sort | uniq -d | head -5 | while read -r dup; do
				echo "    $dup"
			done
		else
			echo "  No duplicate fonts found ✓"
		fi
		
		local corrupted
		corrupted=0
		echo "  Checking for corrupted fonts..."
		local all_fonts
		all_fonts=$(ls /Library/Fonts/*.{ttf,otf} ~/Library/Fonts/*.{ttf,otf} 2>/dev/null || true)
		for font in $all_fonts; do
			[[ ! -f "$font" ]] && continue
			fc-scan "$font" >/dev/null 2>&1 || ((corrupted++))
		done 2>/dev/null || true
		printf "  Corrupted fonts: %s\n" "$corrupted"
	else
		echo "  ${GRAY}Skipped (fontconfig not available)${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	local total=$((sys_fonts + user_fonts))
	echo "  ${GRAY}Total installed: $total fonts${NC}"
	
	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"