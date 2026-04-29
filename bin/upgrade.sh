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
		;;
	esac
done

upgrade_homebrew() {
	print_section_header "Homebrew"

	if ! command -v brew >/dev/null 2>&1; then
		echo "${GRAY}not installed${NC}"
		return 0
	fi

	print_table_header "Manager|Status" 20 20

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$(brew outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			print_table_row "brew|${YELLOW}needs update${NC}"
		else
			print_table_row "brew|${GREEN}up to date${NC}"
		fi
	else
		start_inline_spinner "Updating Homebrew..."
		brew update 2>/dev/null && brew upgrade 2>/dev/null || true
		stop_inline_spinner
		print_table_row "brew|${GREEN}updated${NC}"
	fi
}

upgrade_pip() {
	print_section_header "pip"

	local pip_cmd=""
	if command -v pip3 >/dev/null 2>&1; then
		pip_cmd="pip3"
	elif command -v pip >/dev/null 2>&1; then
		pip_cmd="pip"
	else
		echo "${GRAY}not installed${NC}"
		return 0
	fi

	print_table_header "Manager|Status" 20 20

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$($pip_cmd list --outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			print_table_row "$pip_cmd|${YELLOW}needs update${NC}"
		else
			print_table_row "$pip_cmd|${GREEN}up to date${NC}"
		fi
	else
		start_inline_spinner "Updating pip packages..."
		$pip_cmd list --outdated --format=freeze 2>/dev/null |
			grep -v '^\-e' | cut -d = -f 1 |
			xargs -n1 $pip_cmd install --upgrade 2>/dev/null || true
		stop_inline_spinner
		print_table_row "$pip_cmd|${GREEN}updated${NC}"
	fi
}

upgrade_npm() {
	print_section_header "npm"

	if ! command -v npm >/dev/null 2>&1; then
		echo "${GRAY}not installed${NC}"
		return 0
	fi

	print_table_header "Manager|Status" 20 20

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		npm outdated -g || true
		print_table_row "npm|${YELLOW}check output above${NC}"
	else
		start_inline_spinner "Updating npm packages..."
		npm update -g 2>/dev/null || true
		stop_inline_spinner
		print_table_row "npm|${GREEN}updated${NC}"
	fi
}

upgrade_nvm() {
	print_section_header "nvm"

	local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
	local nvm_sh="$nvm_dir/nvm.sh"

	if [[ ! -s "$nvm_sh" ]]; then
		echo "${GRAY}not installed${NC}"
		return 0
	fi

	print_table_header "Manager|Status" 20 20

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		export NVM_DIR="$nvm_dir"
		source "$nvm_sh"
		local current
		current=$(nvm version current 2>/dev/null || echo "system")
		local latest
		latest=$(nvm version-remote --lts 2>/dev/null || echo "unknown")
		print_table_row "nvm|$current -> $latest"
	else
		export NVM_DIR="$nvm_dir"
		source "$nvm_sh"
		start_inline_spinner "Updating nvm..."
		nvm install --lts 2>/dev/null || true
		stop_inline_spinner
		print_table_row "nvm|${GREEN}updated${NC}"
	fi
}

upgrade_rustup() {
	print_section_header "rustup"

	if ! command -v rustup >/dev/null 2>&1; then
		echo "${GRAY}not installed${NC}"
		return 0
	fi

	print_table_header "Manager|Status" 20 20

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$(rustup check 2>&1 || true)
		if [[ -n "$output" ]]; then
			print_table_row "rustup|${YELLOW}needs update${NC}"
		else
			print_table_row "rustup|${GREEN}up to date${NC}"
		fi
	else
		start_inline_spinner "Updating rustup..."
		rustup update 2>/dev/null || true
		stop_inline_spinner
		print_table_row "rustup|${GREEN}updated${NC}"
	fi
}

upgrade_gem() {
	print_section_header "gem"

	if ! command -v gem >/dev/null 2>&1; then
		echo "${GRAY}not installed${NC}"
		return 0
	fi

	print_table_header "Manager|Status" 20 20

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		local output
		output=$(gem outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			print_table_row "gem|${YELLOW}needs update${NC}"
		else
			print_table_row "gem|${GREEN}up to date${NC}"
		fi
	else
		start_inline_spinner "Updating gem..."
		gem update 2>/dev/null || true
		stop_inline_spinner
		print_table_row "gem|${GREEN}updated${NC}"
	fi
}

main() {
	print_section_header "Upgrade Package Managers"

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		echo "${YELLOW}DRY RUN MODE - no changes made${NC}"
		echo ""
	fi

	upgrade_homebrew
	upgrade_pip
	upgrade_npm
	upgrade_nvm
	upgrade_rustup
	upgrade_gem

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"