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
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

_xcode_derived_bytes() {
	[[ -d "$DERIVED_DATA" ]] || { printf '0'; return 0; }
	du -sk "$DERIVED_DATA" 2>/dev/null | awk '{print $1 * 1024}' || printf '0'
}

# Projects are the entries inside DerivedData. -mindepth 1, or the directory
# itself is counted: "Projects 1" for an empty folder, 4 for 3.
_xcode_derived_projects() {
	[[ -d "$DERIVED_DATA" ]] || { printf '0'; return 0; }
	find "$DERIVED_DATA" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

# The active developer directory, empty when none is selected.
_xcode_dev_dir() {
	xcode-select -p 2>/dev/null || printf ''
}

# Whether Xcode itself is there. `command -v xcrun` is not the test: xcrun is
# part of macOS, restricted, on every Mac, so that guard could never fail and
# a machine with only the Command Line Tools reported installed:true with an
# empty version. Xcode is installed when the selected developer directory
# carries xcodebuild.
_xcode_installed() {
	local dev
	dev=$(_xcode_dev_dir)
	[[ -n "$dev" && -x "$dev/usr/bin/xcodebuild" ]]
}

# Every available simulator, one per line: "name<TAB>booted". The name keeps
# its model — "iPad Pro 11-inch (M4)" and "(M2)" are two devices — and loses
# only the UDID and state that simctl appends. No device filter: Apple Vision
# Pro and iPod touch are simulators too, and the text branch's own copy of
# this (iPhone|iPad, head -10) printed 10 devices where JSON printed 15 and
# simctl 17.
_xcode_simulators() {
	xcrun simctl list devices available 2>/dev/null | awk '
		/^    [^ ]/ {
			line = $0
			sub(/^    /, "", line)
			booted = (line ~ /\(Booted\)$/) ? "true" : "false"
			sub(/ \([0-9A-Fa-f-]{36}\) \([A-Za-z ]+\)$/, "", line)
			print line "\t" booted
		}'
}

# Installed platforms, one basename per line.
_xcode_platforms() {
	local dev
	dev=$(_xcode_dev_dir)
	[[ -n "$dev" && -d "$dev/Platforms" ]] || return 0
	find "$dev/Platforms" -mindepth 1 -maxdepth 1 -name '*.platform' 2>/dev/null |
		sed 's#.*/##; s/\.platform$//' | sort
}

_json_report() {
	local first line name booted platform version build dev
	dev=$(_xcode_dev_dir)

	if ! _xcode_installed; then
		printf '{\n  "installed": false,\n  "developer_dir": %s,\n' "$(rcc_json_string "$dev")"
		printf '  "simulators": [],\n'
		printf '  "derived_data": {"present": %s, "bytes": %s, "projects": %s},\n' \
			"$([[ -d "$DERIVED_DATA" ]] && echo true || echo false)" \
			"$(_xcode_derived_bytes)" "$(_xcode_derived_projects)"
		printf '  "platforms": [],\n  "version": null,\n  "build": null\n}\n'
		return 0
	fi

	printf '{\n  "installed": true,\n  "developer_dir": %s,\n' "$(rcc_json_string "$dev")"

	printf '  "simulators": ['
	first=1
	while IFS=$'\t' read -r name booted; do
		[[ -n "$name" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "booted": %s}' "$(rcc_json_string "$name")" "$booted"
	done < <(_xcode_simulators)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "derived_data": {"present": %s, "bytes": %s, "projects": %s},\n' \
		"$([[ -d "$DERIVED_DATA" ]] && echo true || echo false)" \
		"$(_xcode_derived_bytes)" "$(_xcode_derived_projects)"

	printf '  "platforms": ['
	first=1
	while IFS= read -r platform; do
		[[ -n "$platform" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$platform")"
	done < <(_xcode_platforms)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	version=$(xcodebuild -version 2>/dev/null | head -1 | sed 's/^Xcode //' || printf '')
	build=$(xcodebuild -version 2>/dev/null | sed -n '2p' | sed 's/^Build version //' || printf '')
	printf '  "version": %s,\n' "$(rcc_json_string "$version")"
	printf '  "build": %s\n}\n' "$(rcc_json_string "$build")"
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	print_section_header "Xcode Status"

	if ! _xcode_installed; then
		local dev
		dev=$(_xcode_dev_dir)
		print_table_row "${YELLOW}Xcode is not installed${NC}" 60
		if [[ -n "$dev" ]]; then
			print_table_row "${GRAY}Developer directory: $dev (no xcodebuild there)${NC}" 60
		fi
		print_table_row "${GRAY}Install from App Store${NC}" 60
		if [[ -d "$DERIVED_DATA" ]]; then
			print_table_row "DerivedData left behind: $(du -sh "$DERIVED_DATA" 2>/dev/null | awk '{print $1}')" 60
		fi
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	echo "${GRAY}[1/4] Simulators...${NC}"
	print_table_header "Device|State" 45 10
	local name booted count=0 running=0
	while IFS=$'\t' read -r name booted; do
		[[ -n "$name" ]] || continue
		((count++)) || true
		if [[ "$booted" == true ]]; then
			((running++)) || true
			print_table_row "$name|${GREEN}booted${NC}" 45 10
		else
			print_table_row "$name|${GRAY}shut down${NC}" 45 10
		fi
	done < <(_xcode_simulators)
	if [[ $count -eq 0 ]]; then
		print_table_row "${GRAY}No simulators available${NC}|" 45 10
	else
		print_table_row "${GRAY}Total: $count devices, $running booted${NC}|" 45 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] DerivedData...${NC}"
	print_table_header "Metric|Value" 20 20
	if [[ -d "$DERIVED_DATA" ]]; then
		print_table_row "Size|$(du -sh "$DERIVED_DATA" 2>/dev/null | awk '{print $1}')" 20 20
		print_table_row "Projects|$(_xcode_derived_projects)" 20 20
	else
		print_table_row "DerivedData|${GRAY}not found${NC}" 20 20
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] Device Support...${NC}"
	print_table_header "Installed platform" 40
	local platform pcount=0
	while IFS= read -r platform; do
		[[ -n "$platform" ]] || continue
		((pcount++)) || true
		print_table_row "$platform" 40
	done < <(_xcode_platforms)
	[[ $pcount -gt 0 ]] || print_table_row "${GRAY}Platforms not found${NC}" 40
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Xcode Version...${NC}"
	print_table_header "Version" 40
	local xcode_version
	xcode_version=$(xcodebuild -version 2>/dev/null | head -2 || printf '')
	if [[ -n "$xcode_version" ]]; then
		while IFS= read -r line; do print_table_row "$line" 40; done <<< "$xcode_version"
	else
		print_table_row "${GRAY}Could not determine version${NC}" 40
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
