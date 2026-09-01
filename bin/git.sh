#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_git_help() {
	echo "Usage: rcc git [options]"
	echo ""
	echo "Check local git repositories for issues"
	echo ""
	echo "Options:"
	echo "  --help, -h      Show this help"
	echo "  --json          Output in JSON format"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_git_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

scan_repos() {
	local all_repos=""

	local search_dirs=(
		"$HOME"
		"$HOME/Desktop"
		"$HOME/Documents"
		"$HOME/Developer"
		"$HOME/Projects"
		"$HOME/dev"
		"$HOME/code"
		"$HOME/github"
		"$HOME/workspace"
	)

	for dir in "${search_dirs[@]}"; do
		if [[ -d "$dir" ]]; then
			if [[ "$dir" == "$HOME" ]]; then
				depth=2
			else
				depth=3
			fi
			while IFS= read -r repo; do
				all_repos+=$'\n'"$repo"
			done < <(find "$dir" -maxdepth "$depth" -type d -name '.git' -exec dirname {} \; 2>/dev/null)
		fi
	done

	echo "$all_repos" | sort -u | grep -v '^$'
}

# One record per repository that has something outstanding, as counts rather
# than a rendered sentence: the table and the JSON both need the same numbers,
# and only the table needs them coloured.
#
#   name|path|uncommitted|unpushed|stashed|detached|no_upstream
check_repo() {
	local repo="$1"
	cd "$repo" 2>/dev/null || return 1

	local uncommitted unpushed stashed no_upstream detached=0
	uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
	unpushed=$(git log '@{u}'.. --oneline 2>/dev/null | wc -l | tr -d ' ')
	stashed=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
	git symbolic-ref HEAD >/dev/null 2>&1 || detached=1

	# Count branches with no upstream. The current branch is prefixed with "* "
	# (not whitespace), so the old '^\s+\S' missed it; count every remaining line.
	no_upstream=$(git branch -vv 2>/dev/null | grep -v '\[' | grep -c '.' || true)

	local total=$((uncommitted + unpushed + stashed + detached + no_upstream))
	[[ $total -eq 0 ]] && return 0

	printf '%s|%s|%s|%s|%s|%s|%s\n' \
		"$(basename "$repo")" "$repo" \
		"$uncommitted" "$unpushed" "$stashed" "$detached" "$no_upstream"
}

# The coloured "3 uncommitted, 1 stashed" the table prints, from those counts.
_git_issue_text() {
	local uncommitted="$1" unpushed="$2" stashed="$3" detached="$4" no_upstream="$5"
	local -a parts=()
	[[ "$uncommitted" -gt 0 ]] && parts+=("$uncommitted uncommitted")
	[[ "$unpushed" -gt 0 ]] && parts+=("$unpushed unpushed")
	[[ "$stashed" -gt 0 ]] && parts+=("$stashed stashed")
	[[ "$detached" -eq 1 ]] && parts+=("detached HEAD")
	[[ "$no_upstream" -gt 0 ]] && parts+=("$no_upstream no upstream")

	local out=""
	for part in ${parts[@]+"${parts[@]}"}; do
		[[ -n "$out" ]] && out+=", "
		out+="$part"
	done
	printf '%s%s%s' "${YELLOW}" "$out" "${NC}"
}

_git_json_report() {
	local total="$1"
	shift
	printf '{"repos_total":%s,"repos_with_issues":%s,"repos":[' "$total" "$#"
	local first=1 record
	for record in "$@"; do
		IFS='|' read -r name path uncommitted unpushed stashed detached no_upstream <<<"$record"
		[[ $first -eq 0 ]] && printf ','
		first=0
		printf '{"name":%s,"path":%s,"uncommitted":%s,"unpushed":%s,"stashed":%s,"detached_head":%s,"no_upstream":%s}' \
			"$(rcc_json_string "$name")" "$(rcc_json_string "$path")" \
			"$uncommitted" "$unpushed" "$stashed" \
			"$([[ "$detached" -eq 1 ]] && echo true || echo false)" \
			"$no_upstream"
	done
	printf ']}\n'
}

main() {
	local use_global_progress=false
	if [[ -t 1 && "$JSON_OUTPUT" == "false" ]]; then
		use_global_progress=true
	fi

	if [[ "$use_global_progress" == "true" ]]; then
		init_global_progress 2
		update_global_progress_info "git: scanning for repositories..."
	fi

	local -a repos=()
	while IFS= read -r repo; do
		[[ -z "$repo" ]] && continue
		repos+=("$repo")
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "Found: $repo"
		fi
	done < <(scan_repos)

	if [[ "$use_global_progress" == "true" ]]; then
		increment_global_progress
		update_global_progress_info "git: checking ${#repos[@]} repositories..."
	fi

	local -a repo_issues=()
	local repos_with_issues=0

	# ${repos[@]+"${repos[@]}"} and not "${repos[@]}": in bash 3.2 an empty
	# array expanded under set -u is an unbound variable, not an empty list, so
	# a Mac with no git repositories died here with
	# "repos[@]: unbound variable" instead of printing "No repositories found".
	for repo in ${repos[@]+"${repos[@]}"}; do
		local result
		result=$(check_repo "$repo") || true
		if [[ -n "$result" ]]; then
			((repos_with_issues++)) || true
			repo_issues+=("$result")
			if [[ "$use_global_progress" == "true" ]]; then
				local repo_name="${result%%|*}"
				append_progress_output "$repo_name: has issues"
			fi
		fi
	done

	if [[ "$use_global_progress" == "true" ]]; then
		increment_global_progress
		finish_global_progress
	fi

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		_git_json_report "${#repos[@]}" ${repo_issues[@]+"${repo_issues[@]}"}
		return 0
	fi

	print_section_header "Git Repositories"

	if [[ ${#repos[@]} -eq 0 ]]; then
		echo "${GRAY}No repositories found${NC}"
		return 0
	fi

	print_table_header "Repository|Issues" 40 20

	if [[ $repos_with_issues -eq 0 ]]; then
		print_table_row "All repos|${GREEN}Clean${NC}" 40 20
	else
		for result in ${repo_issues[@]+"${repo_issues[@]}"}; do
			IFS='|' read -r name _ uncommitted unpushed stashed detached no_upstream <<<"$result"
			print_table_row "$name|$(_git_issue_text "$uncommitted" "$unpushed" "$stashed" "$detached" "$no_upstream")" 40 20
		done
	fi

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"