#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_upgrade_help() {
	echo "Usage: rcc upgrade [options]"
	echo ""
	echo "Update package managers: Homebrew, pip, npm, nvm, rustup, gem"
	echo ""
	echo "Options:"
	echo "  --dry-run, -n    Show what would be upgraded without updating"
	echo ""
}

RCC_DRY_RUN=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_upgrade_help
		exit 0
		;;
	--dry-run | -n)
		RCC_DRY_RUN=true
		;;
	*)
		echo "Unknown option: $arg"
		echo "Usage: rcc upgrade [--dry-run]"
		exit 1
		;;
	esac
done

upgrade_homebrew() {
	if ! command -v brew >/dev/null 2>&1; then
		echo -e "${GRAY}skipped (not installed)${NC}"
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$(brew outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			printf '%s\n' "$output" | sed 's/^/    /'
		else
			echo -e "    ${GRAY}All packages up to date${NC}"
		fi
		return 0
	fi

	brew update && brew upgrade
}

upgrade_pip() {
	local pip_cmd=""
	if command -v pip3 >/dev/null 2>&1; then
		pip_cmd="pip3"
	elif command -v pip >/dev/null 2>&1; then
		pip_cmd="pip"
	else
		echo -e "${GRAY}skipped (not installed)${NC}"
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$($pip_cmd list --outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			printf '%s\n' "$output" | sed 's/^/    /'
		else
			echo -e "    ${GRAY}All packages up to date${NC}"
		fi
		return 0
	fi

	$pip_cmd list --outdated --format=freeze 2>/dev/null |
		grep -v '^\-e' | cut -d = -f 1 |
		xargs -n1 $pip_cmd install --upgrade 2>/dev/null || true
}

upgrade_npm() {
	if ! command -v npm >/dev/null 2>&1; then
		echo -e "${GRAY}skipped (not installed)${NC}"
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		npm outdated -g || true
		echo -e "    ${GRAY}Packages to update shown above${NC}"
		return 0
	fi

	npm update -g
}

upgrade_nvm() {
	local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
	local nvm_sh="$nvm_dir/nvm.sh"

	if [[ ! -s "$nvm_sh" ]]; then
		echo -e "${GRAY}skipped (not installed)${NC}"
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		export NVM_DIR="$nvm_dir"
		# shellcheck source=/dev/null
		source "$nvm_sh"
		local current
		current=$(nvm version current 2>/dev/null || echo "system")
		local latest
		latest=$(nvm version-remote --lts 2>/dev/null || echo "unknown")
		echo -e "    Current: ${GRAY}${current}${NC}, Latest LTS: ${GRAY}${latest}${NC}"
		return 0
	fi

	export NVM_DIR="$nvm_dir"
	# shellcheck source=/dev/null
	source "$nvm_sh"
	nvm install --lts
}

upgrade_rustup() {
	if ! command -v rustup >/dev/null 2>&1; then
		echo -e "${GRAY}skipped (not installed)${NC}"
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$(rustup check 2>&1 || true)
		if [[ -n "$output" ]]; then
			printf '%s\n' "$output" | sed 's/^/    /'
		else
			echo -e "    ${GRAY}All toolchains up to date${NC}"
		fi
		return 0
	fi

	rustup update
}

upgrade_gem() {
	if ! command -v gem >/dev/null 2>&1; then
		echo -e "${GRAY}skipped (not installed)${NC}"
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$(gem outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			printf '%s\n' "$output" | sed 's/^/    /'
		else
			echo -e "    ${GRAY}All gems up to date${NC}"
		fi
		return 0
	fi

	gem update
}

main() {
	print_section_header "Upgrade Package Managers"

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, no packages will be updated\n"
	fi

	show_progress_bar \
		"Homebrew:upgrade_homebrew" \
		"pip:upgrade_pip" \
		"npm:upgrade_npm" \
		"nvm:upgrade_nvm" \
		"rustup:upgrade_rustup" \
		"gem:upgrade_gem"
}

main "$@"
