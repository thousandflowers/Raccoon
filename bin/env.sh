#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_env_help() {
	print_help_header "env" "Check environment: PATH entries, broken symlinks, duplicates, tool versions" "[--json]"
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
	echo ""
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_env_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

# The tools worth reporting: the ones a broken PATH breaks first.
ENV_TOOLS=(git curl wget python3 node brew docker)

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

	print_table_row "${GRAY}Total: $count entries, $missing missing${NC}|" 45 10
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
		done < <(find "$path_dir/" -maxdepth 1 -type l 2>/dev/null)
	done <<< "${PATH}:"

	if [[ $total -eq 0 ]]; then
		print_table_row "${GRAY}No broken symlinks found${NC}|" 45 30
	fi
}

# PATH entries listed more than once, one per line, in PATH order. One rule
# for both renderings: the text branch used to keep its own, which printed a
# blank "duplicate" row for an empty element and, on the next line, "No
# duplicates found", while --json reported none.
_env_duplicates() {
	local seen="" dir
	while IFS= read -r -d ':' dir; do
		[[ -z "$dir" ]] && continue
		if printf '%s' "$seen" | grep -qxF "$dir"; then
			printf '%s\n' "$dir"
		else
			seen+=$'\n'"$dir"
		fi
	done <<< "${PATH}:"
}

check_duplicate_path() {
	local dir found=0

	print_section_header "Duplicate PATH Entries"

	print_table_header "Path|Status" 45 10

	while IFS= read -r dir; do
		[[ -n "$dir" ]] || continue
		print_table_row "$dir|${YELLOW}duplicate${NC}" 45 10
		found=1
	done < <(_env_duplicates)

	if [[ $found -eq 0 ]]; then
		print_table_row "${GRAY}No duplicates found${NC}|${GREEN}OK${NC}" 45 10
	fi
}

check_tool_versions() {
	print_section_header "Tool Versions"

	print_table_header "Tool|Version" 15 40

	local tool version
	for tool in "${ENV_TOOLS[@]}"; do
		if version=$(_env_tool_version "$tool"); then
			print_table_row "$tool|$version" 15 40
		else
			print_table_row "$tool|${GRAY}not found${NC}" 15 40
		fi
	done
}

# The first line of `--version`, or "found" for a tool that is on the PATH and
# prints nothing. The old `|| printf 'found'` bound to the pipeline, whose
# status is head's, so it never ran and the row came out empty — which the
# extension then rendered as "not installed".
_env_tool_version() {
	command -v "$1" > /dev/null 2>&1 || return 1
	local version
	version=$("$1" --version 2>/dev/null | head -1 || true)
	printf '%s' "${version:-found}"
}

_json_report() {
	local path_dir link target name version first
	printf '{\n'

	printf '  "path": ['
	first=1
	while IFS= read -r -d ':' path_dir; do
		[[ -z "$path_dir" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"path": %s, "exists": %s}' \
			"$(rcc_json_string "$path_dir")" \
			"$([[ -d "$path_dir" ]] && echo true || echo false)"
	done <<< "${PATH}:"
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	# A symlink whose target is gone: the command is on the PATH and still
	# fails, which is the one thing here that surprises people.
	printf '  "broken_symlinks": ['
	first=1
	while IFS= read -r -d ':' path_dir; do
		[[ -z "$path_dir" || ! -d "$path_dir" ]] && continue
		while IFS= read -r link; do
			[[ -e "$link" ]] && continue
			target=$(readlink "$link" 2>/dev/null || printf '')
			[[ "$target" == /* ]] || target="$(dirname "$link")/$target"
			[[ $first -eq 1 ]] || printf ','
			first=0
			printf '\n    {"name": %s, "link": %s, "target": %s}' \
				"$(rcc_json_string "$(basename "$link")")" \
				"$(rcc_json_string "$link")" \
				"$(rcc_json_string "$target")"
		# The trailing slash matters: a PATH entry that is itself a symlink
		# (~/.local/bin -> somewhere) is never descended into without it, and
		# the broken link inside went uncounted. 4 reported where there were 5.
		done < <(find "$path_dir/" -maxdepth 1 -type l 2>/dev/null || true)
	done <<< "${PATH}:"
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "duplicates": ['
	first=1
	local dir
	while IFS= read -r dir; do
		[[ -n "$dir" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$dir")"
	done < <(_env_duplicates)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "tools": ['
	first=1
	for name in "${ENV_TOOLS[@]}"; do
		[[ $first -eq 1 ]] || printf ','
		first=0
		if version=$(_env_tool_version "$name"); then
			printf '\n    {"name": %s, "found": true, "version": %s}' \
				"$(rcc_json_string "$name")" "$(rcc_json_string "$version")"
		else
			printf '\n    {"name": %s, "found": false, "version": null}' \
				"$(rcc_json_string "$name")"
		fi
	done
	printf '\n  ]\n}\n'
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	show_progress_bar \
		"PATH entries:check_path_entries" \
		"Broken symlinks:check_broken_symlinks" \
		"Duplicates:check_duplicate_path" \
		"Tool versions:check_tool_versions"
}

main "$@"