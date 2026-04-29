#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_xcode_help() {
	echo "Usage: rcc xcode [options]"
	echo ""
	echo "Show Xcode simulators, derived data, and version"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_xcode_help
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
	print_section_header "Xcode Status"

	if ! command -v xcrun >/dev/null 2>&1; then
		print_table_row "${YELLOW}Xcode is not installed${NC}" 40
		print_table_row "${GRAY}Install from App Store${NC}" 40
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	echo "${GRAY}[1/4] iOS Simulators...${NC}"
	echo "  ${GRAY}Available simulators:${NC}"

	local simulators
	simulators=$(xcrun simctl list devices available 2>/dev/null | grep -E "iPhone|iPad" | head -10 || echo "")
	if [[ -n "$simulators" ]]; then
		echo "$simulators" | while read -r line; do
			[[ -z "$line" ]] && continue
			print_table_row "$line" 40
		done
	else
		print_table_row "${GRAY}No simulators found${NC}" 40
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] DerivedData...${NC}"

	local derived_path="$HOME/Library/Developer/Xcode/DerivedData"
	print_table_header "Metric|Value" 20 20

	if [[ -d "$derived_path" ]]; then
		local derived_size
		derived_size=$(du -sh "$derived_path" 2>/dev/null | awk '{print $1}' || echo "unknown")
		local project_count
		project_count=$(ls -1 "$derived_path" 2>/dev/null | wc -l | xargs || echo "0")
		print_table_row "Size|$derived_size" 20 20
		print_table_row "Projects|$project_count" 20 20
	else
		print_table_row "DerivedData|${GRAY}not found${NC}" 20 20
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] Device Support...${NC}"
	echo "  ${GRAY}Installed platforms:${NC}"

	local xcode_path
	xcode_path=$(xcode-select -p 2>/dev/null | sed 's/\/Contents\/Developer//')
	if [[ -n "$xcode_path" && -d "$xcode_path/Platforms" ]]; then
		ls -1 "$xcode_path/Platforms" 2>/dev/null | while read -r platform; do
			[[ -n "$platform" ]] && print_table_row "$platform" 40
		done
	else
		print_table_row "${GRAY}Platforms not found${NC}" 40
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Xcode Version...${NC}"
	echo "  ${GRAY}Version info:${NC}"

	local xcode_version
	xcode_version=$(xcodebuild -version 2>/dev/null | head -2 || echo "Unknown")
	if [[ -n "$xcode_version" ]]; then
		print_table_row "$xcode_version" 40
	else
		printf "| ${GRAY}%-40s${NC} |\n" "Could not determine version"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"