#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_upgrade_help() {
	print_help_header "upgrade" "Update package managers: Homebrew, pip, npm, nvm, rustup, gem" "[--dry-run]"
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
	esac
done

# ============================================================
# Output parsers — extract meaningful info from command lines
# ============================================================

_parse_brew_update() {
	local line="$1"
	if [[ "$line" == *"Updating Homebrew"* ]]; then
		update_global_progress_info "brew: updating..."
	elif [[ "$line" == *"Updated"*tap* ]]; then
		update_global_progress_info "brew: updated taps"
	elif [[ "$line" == *"Already up-to-date"* ]]; then
		update_global_progress_info "brew: up to date"
	fi
}

_parse_brew_upgrade() {
	local line="$1"
	if [[ "$line" == *"==> Upgrading"* ]]; then
		local pkg="${line#*==> Upgrading }"
		update_global_progress_info "brew: upgrade $pkg"
	elif [[ "$line" == *"==> Fetching"* ]]; then
		update_global_progress_info "brew: fetching..."
	elif [[ "$line" == *"==> Downloading"* ]]; then
		update_global_progress_info "brew: downloading..."
	elif [[ "$line" == *"==> Pouring"* ]]; then
		update_global_progress_info "brew: installing..."
	elif [[ "$line" == *"🍺"* ]]; then
		update_global_progress_info "brew: completed"
	elif [[ "$line" == *"==> Caveats"* ]]; then
		update_global_progress_info "brew: caveats"
	fi
}

_parse_pip() {
	local line="$1"
	if [[ "$line" == *"Collecting"* ]]; then
		local pkg
		pkg=$(echo "$line" | sed 's/Collecting //;s/ (.*//')
		update_global_progress_info "pip: collect $pkg"
	elif [[ "$line" == *"Downloading"* ]]; then
		update_global_progress_info "pip: downloading..."
	elif [[ "$line" == *"Installing collected packages"* ]]; then
		update_global_progress_info "pip: installing..."
	elif [[ "$line" == *"Successfully installed"* ]]; then
		update_global_progress_info "pip: installed"
	elif [[ "$line" == *"Requirement already satisfied"* ]]; then
		update_global_progress_info "pip: up to date"
	fi
}

_parse_npm() {
	local line="$1"
	if [[ "$line" == *"added"* || "$line" == *"removed"* || "$line" == *"changed"* ]]; then
		update_global_progress_info "npm: $line"
	elif [[ "$line" == *"packages are looking for funding"* ]]; then
		:
	elif [[ "$line" == *"found"* || "$line" == *"vulnerabilities"* ]]; then
		update_global_progress_info "npm: $line"
	fi
}

_parse_nvm() {
	local line="$1"
	if [[ "$line" == *"Now using"* ]]; then
		update_global_progress_info "nvm: $line"
	elif [[ "$line" == *"Installing"* ]]; then
		update_global_progress_info "nvm: installing..."
	elif [[ "$line" == *"v"* && "$line" == *"already installed"* ]]; then
		update_global_progress_info "nvm: already installed"
	fi
}

_parse_rustup() {
	local line="$1"
	if [[ -n "$line" && "$line" != *"info:"* ]]; then
		update_global_progress_info "rustup: $line"
	elif [[ "$line" == *"updated"* ]]; then
		update_global_progress_info "rustup: updated"
	elif [[ "$line" == *"unchanged"* ]]; then
		update_global_progress_info "rustup: unchanged"
	fi
}

_parse_gem() {
	local line="$1"
	if [[ "$line" == *"Updating"* ]]; then
		update_global_progress_info "gem: $line"
	elif [[ "$line" == *"Nothing to update"* ]]; then
		update_global_progress_info "gem: up to date"
	elif [[ "$line" == *"Gems updated"* ]]; then
		update_global_progress_info "gem: updated"
	fi
}

# ============================================================
# Upgrade functions
# ============================================================

upgrade_homebrew() {
	update_global_progress_info "brew: checking..."

	export HOMEBREW_NO_AUTO_UPDATE=1
	export HOMEBREW_NO_INSTALL_CLEANUP=1
	export GIT_TERMINAL_PROMPT=0

	if ! command -v brew >/dev/null 2>&1; then
		update_global_progress_info "brew: not installed"
		append_progress_output "brew: not installed"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "brew: dry run"
		local output
		output=$(brew outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			append_progress_output "brew: outdated packages found"
			while IFS= read -r line; do
				append_progress_output "$line"
			done <<< "$output"
		else
			append_progress_output "brew: up to date"
		fi
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	update_global_progress_info "brew: updating..."
	brew update 2>&1 </dev/null | progress_pipe _parse_brew_update || true

	increment_global_progress

	update_global_progress_info "brew: upgrading..."
	GIT_TERMINAL_PROMPT=0 brew upgrade 2>&1 </dev/null | progress_pipe _parse_brew_upgrade || true

	increment_global_progress
}

upgrade_pip() {
	update_global_progress_info "pip: checking..."

	local pip_cmd=""
	if command -v pip3 >/dev/null 2>&1; then
		pip_cmd="pip3"
	elif command -v pip >/dev/null 2>&1; then
		pip_cmd="pip"
	else
		update_global_progress_info "pip: not installed"
		append_progress_output "pip: not installed"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "pip: dry run"
		local output
		output=$($pip_cmd list --outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			append_progress_output "pip: outdated packages found"
			while IFS= read -r line; do
				append_progress_output "$line"
			done <<< "$output"
		else
			append_progress_output "pip: up to date"
		fi
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	update_global_progress_info "pip: checking outdated..."
	local pkgs
	pkgs=$($pip_cmd list --outdated --format=freeze 2>/dev/null | grep -v '^\-e' | cut -d = -f 1 || true)

	if [[ -z "$pkgs" ]]; then
		update_global_progress_info "pip: up to date"
		append_progress_output "pip: no outdated packages"
		increment_global_progress
		return 0
	fi

	while IFS= read -r pkg; do
		[[ -z "$pkg" ]] && continue
		update_global_progress_info "pip: upgrade $pkg"
		$pip_cmd install --upgrade "$pkg" 2>&1 | progress_pipe _parse_pip || true
	done <<< "$pkgs"

	increment_global_progress
}

upgrade_npm() {
	update_global_progress_info "npm: checking..."

	if ! command -v npm >/dev/null 2>&1; then
		update_global_progress_info "npm: not installed"
		append_progress_output "npm: not installed"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	# ponytail: check npm prefix writability; can't fix permissions, only warn
	local npm_prefix
	npm_prefix=$(npm config get prefix 2>/dev/null || echo "/usr/local")
	if [[ ! -w "$npm_prefix" ]] && [[ ! -w "${npm_prefix}/lib/node_modules" ]]; then
		append_progress_output "npm: ⚠ prefix $npm_prefix not writable — use nvm or set npm prefix to ~/.npm-global"
		update_global_progress_info "npm: permission error, skipping"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "npm: dry run"
		npm outdated -g 2>&1 | progress_pipe || true
		increment_global_progress
		increment_global_progress
		return 0
	fi

	update_global_progress_info "npm: updating..."
	npm update -g 2>&1 | progress_pipe _parse_npm || true

	increment_global_progress
	increment_global_progress
}

upgrade_nvm() {
	update_global_progress_info "nvm: checking..."

	local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
	local nvm_sh="$nvm_dir/nvm.sh"

	if [[ ! -s "$nvm_sh" ]]; then
		update_global_progress_info "nvm: not installed"
		append_progress_output "nvm: not installed"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	export NVM_DIR="$nvm_dir"
	# shellcheck disable=SC1090
	source "$nvm_sh" >/dev/null 2>&1

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "nvm: dry run"
		local current latest
		current=$(nvm version current 2>/dev/null || echo "system")
		latest=$(nvm version-remote --lts 2>/dev/null || echo "unknown")
		append_progress_output "nvm: $current -> $latest"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	update_global_progress_info "nvm: updating..."
	nvm install --lts 2>&1 | progress_pipe _parse_nvm || true

	increment_global_progress
	increment_global_progress
}

upgrade_rustup() {
	update_global_progress_info "rustup: checking..."

	if ! command -v rustup >/dev/null 2>&1; then
		update_global_progress_info "rustup: not installed"
		append_progress_output "rustup: not installed"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "rustup: dry run"
		local output
		output=$(rustup check 2>&1 || true)
		if [[ -n "$output" ]]; then
			append_progress_output "rustup: check results"
			while IFS= read -r line; do
				append_progress_output "$line"
			done <<< "$output"
		else
			append_progress_output "rustup: up to date"
		fi
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	update_global_progress_info "rustup: updating..."
	rustup update 2>&1 | progress_pipe _parse_rustup || true

	increment_global_progress
}

upgrade_gem() {
	update_global_progress_info "gem: checking..."

	if ! command -v gem >/dev/null 2>&1; then
		update_global_progress_info "gem: not installed"
		append_progress_output "gem: not installed"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	increment_global_progress

	# ponytail: check gem dir writability; can't fix permissions, only warn + suggest --user-install
	local gem_dir
	gem_dir=$(gem environment gemdir 2>/dev/null || echo "/Library/Ruby/Gems")
	if [[ ! -w "$gem_dir" ]]; then
		append_progress_output "gem: ⚠ $gem_dir not writable — use rbenv or gem install --user-install"
		update_global_progress_info "gem: permission error, skipping"
		increment_global_progress
		increment_global_progress
		increment_global_progress
		return 0
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "gem: dry run"
		local output
		output=$(gem outdated 2>&1 || true)
		if [[ -n "$output" ]]; then
			append_progress_output "gem: outdated gems found"
			while IFS= read -r line; do
				append_progress_output "$line"
			done <<< "$output"
		else
			append_progress_output "gem: up to date"
		fi
		increment_global_progress
		increment_global_progress
		return 0
	fi

	update_global_progress_info "gem: updating..."
	gem update 2>&1 | progress_pipe _parse_gem || true

	increment_global_progress
}

# ============================================================
# Fallback output (non-TTY)
# ============================================================

_fallback_upgrade_homebrew() {
	echo ""
	print_section_header "Homebrew"
	if ! command -v brew >/dev/null 2>&1; then
		print_info "not installed"
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		brew outdated 2>&1 || true
	else
		brew update 2>&1 || true
		brew upgrade 2>&1 || true
	fi
}

_fallback_upgrade_pip() {
	echo ""
	print_section_header "pip"
	local pip_cmd=""
	if command -v pip3 >/dev/null 2>&1; then
		pip_cmd="pip3"
	elif command -v pip >/dev/null 2>&1; then
		pip_cmd="pip"
	else
		print_info "not installed"
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		$pip_cmd list --outdated 2>&1 || true
	else
		$pip_cmd list --outdated --format=freeze 2>/dev/null |
			grep -v '^\-e' | cut -d = -f 1 |
			xargs -n1 $pip_cmd install --upgrade 2>&1 || true
	fi
}

_fallback_upgrade_npm() {
	echo ""
	print_section_header "npm"
	if ! command -v npm >/dev/null 2>&1; then
		print_info "not installed"
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		npm outdated -g 2>&1 || true
	else
		npm update -g 2>&1 || true
	fi
}

_fallback_upgrade_nvm() {
	echo ""
	print_section_header "nvm"
	local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
	local nvm_sh="$nvm_dir/nvm.sh"
	if [[ ! -s "$nvm_sh" ]]; then
		print_info "not installed"
		return 0
	fi
	export NVM_DIR="$nvm_dir"
	# shellcheck disable=SC1090
	source "$nvm_sh" >/dev/null 2>&1
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		nvm version current 2>/dev/null || echo "system"
		nvm version-remote --lts 2>/dev/null || echo "unknown"
	else
		nvm install --lts 2>&1 || true
	fi
}

_fallback_upgrade_rustup() {
	echo ""
	print_section_header "rustup"
	if ! command -v rustup >/dev/null 2>&1; then
		print_info "not installed"
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		rustup check 2>&1 || true
	else
		rustup update 2>&1 || true
	fi
}

_fallback_upgrade_gem() {
	echo ""
	print_section_header "gem"
	if ! command -v gem >/dev/null 2>&1; then
		print_info "not installed"
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		gem outdated 2>&1 || true
	else
		gem update 2>&1 || true
	fi
}

# ============================================================
# Main
# ============================================================

main() {
	init_global_progress 18

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

	finish_global_progress
	echo ""
	print_success "Completed"
}

main "$@"
