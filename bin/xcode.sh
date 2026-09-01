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

# shellcheck disable=SC2034
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

# DerivedData is the only thing here worth reclaiming: everything else is a
# fact about the install, not a decision anyone makes.
_xcode_derived_bytes() {
	local path="$HOME/Library/Developer/Xcode/DerivedData"
	[[ -d "$path" ]] || { printf '0'; return 0; }
	du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}' || printf '0'
}

_json_report() {
	local first line name platform version path

	if ! command -v xcrun > /dev/null 2>&1; then
		printf '{\n  "installed": false,\n  "simulators": [],\n'
		printf '  "derived_data": {"present": false, "bytes": 0, "projects": 0},\n'
		printf '  "platforms": [],\n  "version": null,\n  "build": null\n}\n'
		return 0
	fi

	printf '{\n  "installed": true,\n'

	# Booted first: a running simulator is holding memory right now.
	printf '  "simulators": ['
	first=1
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		name=$(printf '%s' "$line" | sed -E 's/^ *//; s/ \(.*//')
		[[ -z "$name" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "booted": %s}' \
			"$(rcc_json_string "$name")" \
			"$(printf '%s' "$line" | grep -q '(Booted)' && echo true || echo false)"
	done < <(xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone|iPad|Apple Watch|Apple TV' || true)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	path="$HOME/Library/Developer/Xcode/DerivedData"
	printf '  "derived_data": {"present": %s, "bytes": %s, "projects": %s},\n' \
		"$([[ -d "$path" ]] && echo true || echo false)" \
		"$(_xcode_derived_bytes)" \
		"$([[ -d "$path" ]] && find "$path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || printf '0')"

	printf '  "platforms": ['
	first=1
	local dev_dir
	dev_dir=$(xcode-select -p 2>/dev/null) || dev_dir=""
	if [[ -n "$dev_dir" && -d "$dev_dir/Platforms" ]]; then
		while IFS= read -r platform; do
			[[ -z "$platform" ]] && continue
			[[ $first -eq 1 ]] || printf ','
			first=0
			printf '\n    %s' "$(rcc_json_string "$(basename "$platform" .platform)")"
		done < <(find "$dev_dir/Platforms" -mindepth 1 -maxdepth 1 -name '*.platform' 2>/dev/null || true)
	fi
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	version=$(xcodebuild -version 2>/dev/null | head -1 | sed 's/^Xcode //' || printf '')
	printf '  "version": %s,\n' "$(rcc_json_string "$version")"
	printf '  "build": %s\n}\n' \
		"$(rcc_json_string "$(xcodebuild -version 2>/dev/null | sed -n '2p' | sed 's/^Build version //' || printf '')")"
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
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
		project_count=$(find "$derived_path" -maxdepth 1 2>/dev/null | wc -l | xargs || echo "0")
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
	# xcode-select -p IS the developer dir (…/Contents/Developer), where
	# Platforms/ lives — don't strip it off, or the dir check below always fails.
	# Exits non-zero when no dev dir is configured, so fall back to empty.
	xcode_path=$(xcode-select -p 2>/dev/null) || xcode_path=""
	if [[ -n "$xcode_path" && -d "$xcode_path/Platforms" ]]; then
		find "$xcode_path/Platforms" -maxdepth 1 2>/dev/null | while read -r platform; do
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