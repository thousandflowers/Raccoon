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
		;;
	esac
done

check_path_entries() {
	local count=0
	local missing=0

	print_section_header "PATH Entries"

	print_table_header "Path|Status" 45 10

	while IFS= read -r -d ':' path; do
		[[ -z "$path" ]] && continue
		((count++)) || true
		if [[ -d "$path" ]]; then
			print_table_row "$path|${GREEN}OK${NC}" 45 10
		else
			print_table_row "$path|${RED}MISSING${NC}" 45 10
			((missing++)) || true
		fi
	done <<< "${PATH}:"

	print_table_row "${GRAY}Total: $count entries, $ missing missing${NC}|" 45 10
}

check_broken_symlinks() {
	local total=0

	print_section_header "Broken Symlinks"

	print_table_header "Symlink|Target" 45 30

	while IFS= read -r -d ':' path_dir; do
		[[ -z "$path_dir" || ! -d "$path_dir" ]] && continue

		while IFS= read -r link; do
			target=$(readlink "$link")
			if [[ "$target" != /* ]]; then
				dir=$(dirname "$link")
				target="$dir/$target"
			fi
			if [[ ! -e "$link" ]]; then
				((total++)) || true
				local link_name
				link_name=$(basename "$link")
				print_table_row "$link_name|${RED}$target${NC}" 45 30
			fi
		done < <(find "$path_dir" -maxdepth 1 -type l 2>/dev/null)
	done <<< "${PATH}:"

	if [[ $total -eq 0 ]]; then
		print_table_row "${GRAY}No broken symlinks found${NC}|" 45 30
	fi
}

check_duplicate_path() {
	local seen=""
	local duplicates=""

	print_section_header "Duplicate PATH Entries"

	print_table_header "Path|Status" 45 10

	IFS=':' read -ra path_parts <<< "$PATH"
	for dir in "${path_parts[@]}"; do
		if echo "$seen" | grep -qxF "$dir"; then
			print_table_row "$dir|${YELLOW}duplicate${NC}" 45 10
		else
			seen+=$'\n'"$dir"
		fi
	done

	if [[ -z "$duplicates" ]]; then
		print_table_row "${GRAY}No duplicates found${NC}|${GREEN}OK${NC}" 45 10
	fi
}

check_tool_versions() {
	print_section_header "Tool Versions"

	print_table_header "Tool|Version" 15 40

	for tool in git curl wget python3 node brew docker; do
		if command -v "$tool" >/dev/null 2>&1; then
			local version
			version=$("$tool" --version 2>/dev/null | head -1 || "$tool" -v 2>/dev/null | head -1 || echo "found")
			print_table_row "$tool|$version" 15 40
		else
			print_table_row "$tool|${GRAY}not found${NC}" 15 40
		fi
	done
}

main() {
	show_progress_bar \
		"PATH entries:check_path_entries" \
		"Broken symlinks:check_broken_symlinks" \
		"Duplicates:check_duplicate_path" \
		"Tool versions:check_tool_versions"
}

main "$@"