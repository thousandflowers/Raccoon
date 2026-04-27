#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

REPOS=""

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
		echo "Unknown option: $arg"
		echo "Usage: rcc git"
		exit 1
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

	REPOS=$(echo "$all_repos" | sort -u | grep -v '^$' | tr '\n' $'\n')
}

check_repos() {
	if [[ -z "$REPOS" ]]; then
		echo -e "  ${GRAY}No repositories found${NC}"
		return 0
	fi

	local repos_with_issues=0

	while IFS= read -r repo; do
		local has_issue=0
		local output=""

		cd "$repo"

		local uncommitted
		uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
		if [[ "$uncommitted" -gt 0 ]]; then
			has_issue=1
			output+="  ${YELLOW}${ICON_SKIP}${NC} $uncommitted uncommitted changes"$'\n'
		fi

		local unpushed
		unpushed=$(git log @{u}.. --oneline 2>/dev/null | wc -l | tr -d ' ')
		if [[ "$unpushed" -gt 0 ]]; then
			has_issue=1
			output+="  ${YELLOW}${ICON_SKIP}${NC} $unpushed unpushed commits"$'\n'
		fi

		local stashed
		stashed=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
		if [[ "$stashed" -gt 0 ]]; then
			has_issue=1
			output+="  ${YELLOW}${ICON_SKIP}${NC} $stashed stash"$'\n'
		fi

		if ! git symbolic-ref HEAD >/dev/null 2>&1; then
			has_issue=1
			output+="  ${YELLOW}${ICON_SKIP}${NC} detached HEAD"$'\n'
		fi

		if [[ $has_issue -eq 1 ]]; then
			((repos_with_issues++))
			echo ""
			echo "$repo"
			printf "%b" "$output"
		fi

	done <<< "$REPOS"

	if [[ $repos_with_issues -eq 0 ]]; then
		echo ""
		echo -e "  ${GREEN}${ICON_SUCCESS} All repositories are clean${NC}"
	else
		echo ""
		echo "  Found $repos_with_issues repositories with issues"
	fi
}

main() {
	print_section_header "Git Repository Check"

	show_progress_bar \
		"Scanning repos:scan_repos" \
		"Checking status:check_repos"
}

main "$@"