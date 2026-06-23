#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_apps_help() {
	print_help_header "apps" "Update installed GUI apps" "[--dry-run]"
	echo "  --dry-run, -n    Show what would be updated without updating"
	echo ""
	echo "  Updates: Mac App Store (mas) + Homebrew casks (--greedy)"
	echo "  Greedy also refreshes apps that normally self-update."
	echo ""
}

RCC_DRY_RUN=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_apps_help
		exit 0
		;;
	--dry-run | -n)
		RCC_DRY_RUN=true
		;;
	esac
done

# ============================================================
# Output parsers
# ============================================================

_parse_cask() {
	local line="$1"
	case "$line" in
	*"==> Upgrading"*) update_global_progress_info "cask: ${line#*==> Upgrading }" ;;
	*"==> Downloading"*) update_global_progress_info "cask: downloading..." ;;
	*"==> Installing"* | *"==> Moving"*) update_global_progress_info "cask: installing..." ;;
	esac
}

_parse_mas() {
	local line="$1"
	[[ -n "$line" ]] && update_global_progress_info "mas: $line"
}

# ============================================================
# Updaters — each increments global progress exactly twice
# ============================================================

update_casks() {
	update_global_progress_info "casks: checking..."

	export HOMEBREW_NO_AUTO_UPDATE=1
	export HOMEBREW_NO_INSTALL_CLEANUP=1
	export GIT_TERMINAL_PROMPT=0

	if ! command -v brew >/dev/null 2>&1; then
		append_progress_output "casks: brew not installed"
		increment_global_progress
		increment_global_progress
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "casks: dry run"
		local output
		output=$(brew outdated --cask --greedy 2>&1 || true)
		if [[ -n "$output" ]]; then
			append_progress_output "casks: outdated apps found"
			while IFS= read -r line; do
				append_progress_output "$line"
			done <<<"$output"
		else
			append_progress_output "casks: up to date"
		fi
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress
	update_global_progress_info "casks: upgrading..."
	# ponytail: --greedy may prompt sudo for some casks; same as `rcc upgrade`
	brew upgrade --cask --greedy 2>&1 </dev/null | progress_pipe _parse_cask || true
	increment_global_progress
}

update_mas() {
	update_global_progress_info "mas: checking..."

	# mas prints spurious "not indexed in Spotlight" warnings to stderr for
	# every App Store app; we capture 2>&1, so without this they flood the
	# buffer and get mislabeled "outdated apps found". mas's own fix:
	export MAS_NO_AUTO_INDEX=1

	if ! command -v mas >/dev/null 2>&1; then
		append_progress_output "mas: not installed — run 'brew install mas'"
		increment_global_progress
		increment_global_progress
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "mas: dry run"
		local output
		output=$(mas outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			append_progress_output "mas: outdated apps found"
			while IFS= read -r line; do
				append_progress_output "$line"
			done <<<"$output"
		else
			append_progress_output "mas: up to date"
		fi
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress
	update_global_progress_info "mas: upgrading..."
	mas upgrade 2>&1 | progress_pipe _parse_mas || true
	increment_global_progress
}

# ============================================================
# Main
# ============================================================

main() {
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		echo "${YELLOW}DRY RUN MODE - no changes made${NC}"
		echo ""
	fi

	# ponytail: 2 slots per updater
	init_global_progress 4

	update_casks
	update_mas

	finish_global_progress
	echo ""

	print_success "Completed"
}

main "$@"
