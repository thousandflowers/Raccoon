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
		echo "${YELLOW}Xcode is not installed${NC}"
		echo "${GRAY}Install from App Store or https://developer.apple.com/xcode/${NC}"
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	echo "${GRAY}[1/4] iOS Simulators...${NC}"
	local simulators
	simulators=$(xcrun simctl list devices available 2>/dev/null | grep -E "iPhone|iPad" | head -10 || echo "")
	if [[ -n "$simulators" ]]; then
		echo "$simulators" | while read -r line; do
			[[ -z "$line" ]] && continue
			echo "  $line"
		done
	else
		echo "  ${GRAY}No simulators found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] DerivedData...${NC}"
	local derived_path="$HOME/Library/Developer/Xcode/DerivedData"
	if [[ -d "$derived_path" ]]; then
		local derived_size
		derived_size=$(du -sh "$derived_path" 2>/dev/null | awk '{print $1}' || echo "unknown")
		local project_count
		project_count=$(ls -1 "$derived_path" 2>/dev/null | wc -l | xargs || echo "0")
		printf "  Size: %s\n" "$derived_size"
		printf "  Projects: %s\n" "$project_count"
	else
		echo "  ${GRAY}DerivedData folder not found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] Device Support...${NC}"
	local xcode_path
	xcode_path=$(xcode-select -p 2>/dev/null | sed 's/\/Contents\/Developer//')
	if [[ -n "$xcode_path" && -d "$xcode_path/Platforms" ]]; then
		ls -1 "$xcode_path/Platforms" 2>/dev/null | while read -r platform; do
			[[ -n "$platform" ]] && echo "  $platform"
		done
	else
		echo "  ${GRAY}Platforms not found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Xcode Version...${NC}"
	local xcode_version
	xcode_version=$(xcodebuild -version 2>/dev/null | head -2 || echo "Unknown")
	if [[ -n "$xcode_version" ]]; then
		echo "$xcode_version" | while read -r line; do
			[[ -n "$line" ]] && echo "  $line"
		done
	else
		echo "  ${GRAY}Could not determine Xcode version${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
