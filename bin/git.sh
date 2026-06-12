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
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_git_help
		exit 0
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

check_repo() {
	local repo="$1"
	cd "$repo" 2>/dev/null || return 1

	local has_issue=0
	local issues=""

	local uncommitted
	uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
	if [[ "$uncommitted" -gt 0 ]]; then
		has_issue=1
		issues+="${YELLOW}$uncommitted uncommitted${NC}, "
	fi

	local unpushed
	unpushed=$(git log '@{u}'.. --oneline 2>/dev/null | wc -l | tr -d ' ')
	if [[ "$unpushed" -gt 0 ]]; then
		has_issue=1
		issues+="${YELLOW}$unpushed unpushed${NC}, "
	fi

	local stashed
	stashed=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
	if [[ "$stashed" -gt 0 ]]; then
		has_issue=1
		issues+="${YELLOW}$stashed stashed${NC}, "
	fi

	if ! git symbolic-ref HEAD >/dev/null 2>&1; then
		has_issue=1
		issues+="${YELLOW}detached HEAD${NC}, "
	fi

	local no_upstream
	no_upstream=$(git branch -vv 2>/dev/null | grep -v '\[' | grep -cE '^\s+\S' || true)
	if [[ "$no_upstream" -gt 0 ]]; then
		has_issue=1
		issues+="${YELLOW}$no_upstream no upstream${NC}"
	fi

	if [[ $has_issue -eq 1 ]]; then
		local repo_name
		repo_name=$(basename "$repo")
		echo "$repo_name|$issues"
	fi
}

main() {
	local use_global_progress=false
	if [[ -t 1 ]]; then
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

	for repo in "${repos[@]}"; do
		local result
		result=$(check_repo "$repo")
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

	print_section_header "Git Repositories"

	if [[ ${#repos[@]} -eq 0 ]]; then
		echo "${GRAY}No repositories found${NC}"
		return 0
	fi

	print_table_header "Repository|Issues" 40 20

	if [[ $repos_with_issues -eq 0 ]]; then
		print_table_row "All repos|${GREEN}Clean${NC}" 40 20
	else
		for result in "${repo_issues[@]}"; do
			print_table_row "$result" 40 20
		done
	fi

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"