#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_env_help() {
	echo "Usage: rcc env [options]"
	echo ""
	echo "Check environment: PATH entries, broken symlinks, duplicates, tool versions"
	echo ""
	echo "Options:"
	echo "  --help, -h      Show this help"
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_env_help
		exit 0
		;;
	*)
		echo "Unknown option: $arg"
		echo "Usage: rcc env"
		exit 1
		;;
	esac
done

check_path_entries() {
	local count=0
	local missing=0

	echo ""
	echo "PATH Entries"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	while IFS= read -r -d ':' path; do
		[[ -z "$path" ]] && continue
		((count++))
		if [[ -d "$path" ]]; then
			echo -e "  ${GRAY}$path${NC}"
		else
			echo -e "  ${RED}${ICON_ERROR} $path${NC}"
			((missing++))
		fi
	done <<< "${PATH}:"

	echo "  ─────────────────────────────────"
	echo "  Total: $count entries, ${missing} missing"
}

check_broken_symlinks() {
	local total=0

	echo ""
	echo "Broken Symlinks in PATH"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	while IFS= read -r -d ':' path_dir; do
		[[ -z "$path_dir" || ! -d "$path_dir" ]] && continue

		while IFS= read -r link; do
			target=$(readlink "$link")
			if [[ "$target" != /* ]]; then
				dir=$(dirname "$link")
				target="$dir/$target"
			fi
			if [[ ! -e "$link" ]]; then
				((total++))
				echo -e "  ${RED}${ICON_ERROR} $link -> $(readlink "$link")${NC}"
			fi
		done < <(find "$path_dir" -maxdepth 1 -type l 2>/dev/null)
	done <<< "${PATH}:"

	if [[ $total -eq 0 ]]; then
		echo -e "  ${GRAY}No broken symlinks found${NC}"
	fi
}

check_duplicate_path() {
	local seen=""
	local duplicates=""

	echo ""
	echo "Duplicate PATH Entries"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	IFS=':' read -ra path_parts <<< "$PATH"
	for dir in "${path_parts[@]}"; do
		if echo "$seen" | grep -qxF "$dir"; then
			duplicates+="  ${YELLOW}$dir (duplicate)${NC}"$'\n'
		else
			seen+=$'\n'"$dir"
		fi
	done

	if [[ -z "$duplicates" ]]; then
		echo -e "  ${GRAY}No duplicates found${NC}"
	else
		printf "%b" "$duplicates"
	fi
}

check_tool_versions() {
	echo ""
	echo "Tool Versions"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	for tool in git curl wget python3 node brew docker; do
		if command -v "$tool" >/dev/null 2>&1; then
			local version
			version=$("$tool" --version 2>/dev/null | head -1 || "$tool" -v 2>/dev/null | head -1 || echo "found")
			echo -e "  ${GREEN}$tool${NC}  $version"
		else
			echo -e "  ${GRAY}$tool${NC}  not found"
		fi
	done
}

main() {
	print_section_header "Environment Check"

	show_progress_bar \
		"PATH entries:check_path_entries" \
		"Broken symlinks:check_broken_symlinks" \
		"Duplicates:check_duplicate_path" \
		"Tool versions:check_tool_versions"
}

main "$@"