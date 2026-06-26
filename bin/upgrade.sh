#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_upgrade_help() {
	print_help_header "upgrade" "Update package managers and tools" "[--dry-run]"
	echo "  --dry-run, -n    Show what would be upgraded without updating"
	echo ""
	echo "  Tracked: brew pip npm pnpm bun uv go nvm rustup gem docker claude"
	echo ""
}

# RACCOON_TEST is set by the bats harness: never run real upgrades under it
# (the suite invokes this with bad/empty args to test parsing, not to upgrade).
if [[ -n "${RACCOON_TEST:-}" ]]; then RCC_DRY_RUN=true; else RCC_DRY_RUN=false; fi
RCC_DEFERRED_TAPS=()

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
	# Specific outcomes first: the generic non-"info:" catch-all below would
	# otherwise swallow "updated"/"unchanged" lines and print them raw.
	if [[ "$line" == *"updated"* ]]; then
		update_global_progress_info "rustup: updated"
	elif [[ "$line" == *"unchanged"* ]]; then
		update_global_progress_info "rustup: unchanged"
	elif [[ -n "$line" && "$line" != *"info:"* ]]; then
		update_global_progress_info "rustup: $line"
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
	# Same sudo-prompt safety as `rcc apps` (issue #23): never feed sudo /dev/null
	# (instant EOF -> empty password -> rejection without Touch ID). Use the
	# controlling TTY when present, fall back to /dev/null only when headless.
	local brew_stdin=/dev/null
	if { true >/dev/tty; } 2>/dev/null; then
		brew_stdin=/dev/tty
	fi
	GIT_TERMINAL_PROMPT=0 brew upgrade <"$brew_stdin" | progress_pipe _parse_brew_upgrade || true

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

	# ponytail: check npm prefix writability; fallback to sudo instead of skip
	local npm_prefix npm_sudo
	npm_prefix=$(npm config get prefix 2>/dev/null || echo "/usr/local")
	npm_sudo=""
	if [[ ! -w "$npm_prefix" ]] && [[ ! -w "${npm_prefix}/lib/node_modules" ]]; then
		append_progress_output "npm: prefix $npm_prefix not writable, trying sudo"
		npm_sudo="sudo"
	fi

	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "npm: dry run"
		$npm_sudo npm outdated -g 2>&1 | progress_pipe || true
		increment_global_progress
		increment_global_progress
		return 0
	fi

	update_global_progress_info "npm: updating..."
	$npm_sudo npm update -g 2>&1 | progress_pipe _parse_npm || true

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
		# 3 slots total with the increment at line 366 above (matches every other gem path).
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

	# 3 slots total with the increment at line 366 above (matches every other gem path).
	increment_global_progress
	increment_global_progress
}

upgrade_pnpm() {
	update_global_progress_info "pnpm: checking..."
	if ! command -v pnpm >/dev/null 2>&1; then
		append_progress_output "pnpm: not installed"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "pnpm: dry run"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	update_global_progress_info "pnpm: updating..."
	pnpm up -g 2>&1 | progress_pipe || true
	increment_global_progress
	increment_global_progress
}

upgrade_bun() {
	update_global_progress_info "bun: checking..."
	if ! command -v bun >/dev/null 2>&1; then
		append_progress_output "bun: not installed"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "bun: dry run"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	update_global_progress_info "bun: updating..."
	bun upgrade 2>&1 | progress_pipe || true
	increment_global_progress
	increment_global_progress
}

upgrade_uv() {
	update_global_progress_info "uv: checking..."
	if ! command -v uv >/dev/null 2>&1; then
		append_progress_output "uv: not installed"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "uv: dry run"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	update_global_progress_info "uv: updating..."
	uv self update 2>&1 | progress_pipe || true
	increment_global_progress
	# ponytail: tool upgrade is best-effort, ignore failures
	uv tool upgrade --all 2>&1 | progress_pipe || true
	increment_global_progress
}

upgrade_go() {
	update_global_progress_info "go: checking..."
	if ! command -v go >/dev/null 2>&1; then
		append_progress_output "go: not installed"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	update_global_progress_info "go: $(go version 2>/dev/null | awk '{print $3}')"
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		increment_global_progress
		increment_global_progress
		return 0
	fi
	# ponytail: only update gopls and goimports — well-known Go tools
	# 2 slots total (one per tool), matching the not-installed and dry-run paths.
	update_global_progress_info "go: updating gopls..."
	go install golang.org/x/tools/gopls@latest 2>&1 | progress_pipe || true
	increment_global_progress
	update_global_progress_info "go: updating goimports..."
	go install golang.org/x/tools/cmd/goimports@latest 2>&1 | progress_pipe || true
	increment_global_progress
}

upgrade_docker() {
	update_global_progress_info "docker: checking..."
	if ! command -v docker >/dev/null 2>&1; then
		append_progress_output "docker: not installed"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "docker: dry run"
		append_progress_output "docker: would prune images"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	# ponytail: prune images older than 24h — safe for daily runs
	update_global_progress_info "docker: pruning images >24h..."
	docker image prune -af --filter until=24h 2>&1 | progress_pipe || true
	increment_global_progress
	increment_global_progress
}

upgrade_claude() {
	update_global_progress_info "claude: checking..."
	if ! command -v claude >/dev/null 2>&1; then
		append_progress_output "claude: not installed"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		update_global_progress_info "claude: dry run"
		increment_global_progress
		increment_global_progress
		return 0
	fi
	update_global_progress_info "claude: updating..."
	claude update 2>&1 | progress_pipe || true
	increment_global_progress
	increment_global_progress
}

# ============================================================
# Main
# ============================================================

_check_taps_preflight() {
	# ponytail: skip preflight in non-TTY (tests, pipes)
	if ! [[ -t 1 ]]; then
		return 0
	fi
	if ! command -v brew >/dev/null 2>&1; then
		return 0
	fi
	# ponytail: brew tap-info --json fetches remote data; use local CSV
	while IFS= read -r tap; do
		[[ -z "$tap" ]] && continue
		[[ "$tap" == homebrew/* ]] && continue
		# brew tap-info line: "<tap>: Installed" then "Untrusted" underneath
		if ! brew tap-info "$tap" 2>/dev/null | grep -qx "Untrusted"; then
			continue
		fi
		if [[ -t 0 ]]; then
			echo -n "Trust tap ${tap}? (Y/n) [auto-defer 10s]: "
			read -t 10 -r response || true
			case "${response:-y}" in
				[Yy]*|"") brew tap --trust "$tap" 2>/dev/null || RCC_DEFERRED_TAPS+=("$tap") ;;
				*) RCC_DEFERRED_TAPS+=("$tap") ;;
			esac
		else
			RCC_DEFERRED_TAPS+=("$tap")
		fi
	done < <(brew tap 2>/dev/null || true)

	if [[ ${#RCC_DEFERRED_TAPS[@]} -gt 0 ]]; then
		echo ""
		echo "Deferred tap trust requests (will process after all upgrades):"
		for tap in "${RCC_DEFERRED_TAPS[@]}"; do
			echo "  ${tap}"
		done
		echo ""
	fi
}

_show_deferred_taps() {
	if [[ ${#RCC_DEFERRED_TAPS[@]} -eq 0 ]]; then
		return 0
	fi
	echo ""
	echo "=== Deferred Tap Trust ==="
	for tap in "${RCC_DEFERRED_TAPS[@]}"; do
		if [[ -t 0 ]]; then
			echo -n "Trust ${tap}? (Y/n): "
			read -r response || true
			case "${response:-y}" in
				[Yy]*|"")
					brew tap --trust "$tap" 2>/dev/null || echo "  ✗ Failed to trust $tap"
					;;
				*) echo "  Skipped ${tap}" ;;
			esac
		fi
	done
}

main() {
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		echo "${YELLOW}DRY RUN MODE - no changes made${NC}"
		echo ""
	fi

	# Pre-flight: handle tap trust before progress bar
	_check_taps_preflight

	# Cache sudo up front (Touch ID when available) so cask upgrades that need
	# root actually complete. Mid-progress the 200ms redraw overwrites any sudo
	# prompt, so the upgrade would silently stall and the package not update.
	if [[ "$RCC_DRY_RUN" != "true" ]] && command -v brew >/dev/null 2>&1; then
		if ensure_sudo; then
			# Refresh the timestamp across the whole (possibly >5min) run so a
			# cask/npm sudo never re-prompts mid-progress and gets garbled.
			trap stop_sudo_keepalive EXIT
			start_sudo_keepalive
		else
			echo "${YELLOW}⚠ sudo unavailable — casks needing root may be skipped${NC}"
		fi
	fi

	# ponytail: one progress slot per upgrade function
	init_global_progress 30

	upgrade_homebrew
	upgrade_pip
	upgrade_npm
	upgrade_pnpm
	upgrade_bun
	upgrade_uv
	upgrade_go
	upgrade_nvm
	upgrade_rustup
	upgrade_gem
	upgrade_docker
	upgrade_claude

	finish_global_progress
	echo ""

	_show_deferred_taps

	print_success "Completed"
}

main "$@"
