#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_apps_help() {
	print_help_header "apps" "Update installed GUI apps" "[options]"
	echo "  Updates all apps in four layers, in order:"
	echo "    1. Mac App Store      (mas)"
	echo "    2. Homebrew casks     (brew upgrade --cask --greedy)"
	echo "    3. Homebrew catalog   (7000+ apps matched by name, no install needed)"
	echo "    4. Sparkle feed       (apps with SUFeedURL: opened, they update themselves)"
	echo ""
	echo "  Apps with a built-in auto-updater (Slack, Chrome, Zoom...) are updated"
	echo "  via Homebrew like everything else, since their internal updater often"
	echo "  lags. Use --auto-launch to instead open them so their own updater runs."
	echo ""
	echo "  Layer 4 never installs anything. Those apps ship Sparkle, which swaps"
	echo "  the bundle atomically and verifies its signature; rcc only tells you an"
	echo "  update exists and opens the app so its own updater can take over."
	echo "  Nothing in this command writes to /Applications."
	echo ""
	echo "  Options:"
	echo "    --dry-run, -n    Show what would be updated, without updating"
	echo "    --no-catalog     Skip the Homebrew catalog lookup (layer 3)"
	echo "    --no-sparkle     Skip the Sparkle feed check (layer 4)"
	echo "    --auto-launch    Open auto-updater apps instead of updating via brew"
	echo "    --help, -h       This help"
	echo ""
	echo "  Sparkle feeds are fetched concurrently and the cask catalog is cached"
	echo "  in ~/.raccoon for a day; both are read-only, so nothing is installed"
	echo "  any faster or in a different order. RCC_FETCH_JOBS sets how many feeds"
	echo "  are fetched at once (default 8) — lower it on a slow link."
	echo ""
	echo "  Command-line tools are not touched here — use 'rcc upgrade'."
	echo ""
}

# RACCOON_TEST is set by the bats harness: never perform real updates under it
# (the suite invokes this with bad/empty args to test parsing, not to update).
# Honour an inherited RCC_DRY_RUN: the rest of the script reads it as a knob, so
# hard-resetting it here made `RCC_DRY_RUN=true rcc upgrade` silently run for
# real. --dry-run still sets it, and tests always force it on.
RCC_DRY_RUN="${RCC_DRY_RUN:-false}"
[[ -n "${RACCOON_TEST:-}" ]] && RCC_DRY_RUN=true
RCC_NO_CATALOG=false
RCC_NO_SPARKLE=false
RCC_AUTO_LAUNCH=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_apps_help
		exit 0
		;;
	--dry-run | -n)
		RCC_DRY_RUN=true
		;;
	--no-catalog)
		RCC_NO_CATALOG=true
		;;
	--no-sparkle)
		RCC_NO_SPARKLE=true
		;;
	--auto-launch)
		RCC_AUTO_LAUNCH=true
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
# Layer 1-2 — Mac App Store + Homebrew casks (each increments twice)
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
	# brew --cask --greedy can re-invoke sudo for casks that need root. main()
	# pre-caches sudo and a keepalive holds the timestamp for the whole run, so a
	# prompt here is rare. When one does happen it must reach a real terminal:
	# `</dev/null` hands sudo an instant EOF -> empty password -> rejection for
	# users WITHOUT Touch ID (part of issue #23).
	# Under RCC_NO_PROMPT the terminal belongs to the TUI, which is redrawing the
	# progress bar every 200ms and reading keys itself — a prompt raised there is
	# unanswerable and loops on "Sorry, try again", so fail the cask fast instead.
	# No 2>&1: keep sudo's prompt on the terminal instead of swallowing it into
	# the progress pipe.
	local brew_stdin=/dev/null
	if [[ "${RCC_NO_PROMPT:-}" != "1" ]] && has_tty; then
		brew_stdin=/dev/tty
	fi
	brew upgrade --cask --greedy <"$brew_stdin" | progress_pipe _parse_cask || true
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
# Catalog helpers (pure bash / awk / grep — no python/jq)
# ============================================================

# Build a token<TAB>app_name<TAB>version<TAB>auto_updates lookup from the
# Homebrew cask catalog JSON (one cask per line). Skips deprecated/disabled.
_build_cask_lookup() {
	grep -v '"deprecated":true' "$CASK_CATALOG_FILE" 2>/dev/null |
		grep -v '"disabled":true' |
		awk '
			# Value of the FIRST  "key":"<value>"  on the line. Greedy ".*key" would
			# grab the LAST occurrence — and casks carry per-OS "variations" blocks
			# with their own (older) "version", so the last one is a stale fallback
			# (e.g. vscode 1.97.2 instead of 1.126.0). match() is leftmost, so the
			# top-level current value wins.
			function firstval(line, pat,   m) {
				if (match(line, pat "\"[^\"]*\"")) {
					m = substr(line, RSTART, RLENGTH)
					sub(pat "\"", "", m); sub(/"$/, "", m)
					return m
				}
				return ""
			}
			{
				line = $0
				token = firstval(line, "\"token\":")
				if (token == "") next
				ver = firstval(line, "\"version\":")
				auto = "0"; if (line ~ /"auto_updates":true/) auto = "1"
				key = ""
				if (match(line, /"app":\["[^"]*"/)) {
					key = substr(line, RSTART, RLENGTH)
					sub(/"app":\["/, "", key); sub(/"$/, "", key)   # e.g. "Foo.app"
				} else if (match(line, /"name":\["[^"]*"/)) {
					# pkg/installer casks ship no ".app" artifact; fall back to the
					# display name so a bundle named "<name>.app" still matches and
					# updates via brew (recovers Teams / Multipass-class apps).
					# ponytail: best-effort — a generic cask name could collide; the
					# version gate + no-downgrade keep a wrong match from doing harm.
					key = substr(line, RSTART, RLENGTH)
					sub(/"name":\["/, "", key); sub(/"$/, "", key)
					key = key ".app"
				}
				if (key != "") print token "\t" key "\t" ver "\t" auto
			}
		' >"$CASK_LOOKUP_FILE" 2>/dev/null || true
}

# Look up "<Name>.app" (column 2, tab-delimited) and print its lookup row, or "".
_lookup_app() {
	local tab
	tab="$(printf '\t')"
	grep -iF "${tab}${1}${tab}" "$CASK_LOOKUP_FILE" 2>/dev/null | head -1 || true
}

# Print an .app bundle's version (CFBundleShortVersionString, then CFBundleVersion).
_local_version() {
	defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null ||
		defaults read "$1/Contents/Info" CFBundleVersion 2>/dev/null ||
		echo ""
}

# Return 0 (true) when $1 (local) is older than $2 (remote). Bash 3.2 safe:
# field-by-field on dots, no sort -V (unavailable on BSD sort).
_version_outdated() {
	[[ "$1" == "$2" ]] && return 1
	local IFS=.
	# shellcheck disable=SC2206  # intentional split of dotted version into fields
	local -a L=($1) R=($2)
	local i l r
	for i in 0 1 2 3; do
		l="${L[$i]:-0}"
		r="${R[$i]:-0}"
		l="${l%%[^0-9]*}"
		r="${r%%[^0-9]*}"
		l="${l:-0}"
		r="${r:-0}"
		((l < r)) && return 0
		((l > r)) && return 1
	done
	return 1
}

# Directories scanned for .app bundles. Overridable for testing.
_app_dirs() {
	if [[ -n "${RCC_APP_DIRS:-}" ]]; then
		printf '%s' "$RCC_APP_DIRS"
	else
		printf '%s' "/Applications $HOME/Applications"
	fi
}

# ============================================================
# Layer 3 — Homebrew catalog (match installed apps by name)
# ============================================================

update_homebrew_catalog() {
	# Guard: no catalog available.
	if [[ -z "${CASK_CATALOG_FILE:-}" ]]; then
		increment_global_progress
		increment_global_progress
		return 0
	fi

	update_global_progress_info "catalog: building lookup..."
	if [[ ! -s "${CASK_LOOKUP_FILE:-}" ]]; then
		CASK_LOOKUP_FILE="$(mktemp /tmp/raccoon-lu-XXXXXX)"
		_build_cask_lookup
	fi
	increment_global_progress

	update_global_progress_info "catalog: scanning Applications..."

	# Casks already handled by layer 2 — skip those tokens.
	local brew_casks=""
	command -v brew >/dev/null 2>&1 && brew_casks="$(brew list --cask 2>/dev/null || true)"

	local updated=0 launched=0 skipped=0 not_found=0
	local app_dir app_path app_name match token remote_ver auto local_ver

	# shellcheck disable=SC2046  # intentional word-split of the dir list
	for app_dir in $(_app_dirs); do
		[[ -d "$app_dir" ]] || continue
		for app_path in "$app_dir"/*.app; do
			[[ -d "$app_path" ]] || continue
			app_name="$(basename "$app_path" .app)"

			match="$(_lookup_app "${app_name}.app")"
			if [[ -z "$match" ]]; then
				((not_found++)) || true
				continue
			fi

			token="$(echo "$match" | cut -f1)"
			remote_ver="$(echo "$match" | cut -f3)"
			# Homebrew cask versions carry a ",revision" / ":checksum" suffix
			# (e.g. "4.79.0,230596"); drop it for a clean display and compare.
			remote_ver="${remote_ver%%,*}"
			remote_ver="${remote_ver%%:*}"
			auto="$(echo "$match" | cut -f4)"

			if echo "$brew_casks" | grep -qx "$token" 2>/dev/null; then
				((skipped++)) || true
				continue
			fi

			local_ver="$(_local_version "$app_path")"
			[[ -z "$local_ver" ]] && continue

			if ! _version_outdated "$local_ver" "$remote_ver"; then
				((skipped++)) || true
				continue
			fi

			# Apps with a built-in auto-updater are still updated via brew cask by
			# default — their internal updater often lags badly (stale Claude /
			# Docker / Figma was the bug report). --auto-launch opts into opening
			# the app so its own updater runs instead, matching `brew --greedy`.
			local use_autolaunch=false
			[[ "$auto" == "1" && "${RCC_AUTO_LAUNCH:-false}" == "true" ]] && use_autolaunch=true

			if [[ "$RCC_DRY_RUN" == "true" ]]; then
				if [[ "$use_autolaunch" == "true" ]]; then
					append_progress_output "catalog: $app_name $local_ver — will open to trigger its auto-updater"
				else
					append_progress_output "catalog: $app_name $local_ver → $remote_ver"
				fi
				continue
			fi

			if [[ "$use_autolaunch" == "true" ]]; then
				update_global_progress_info "catalog: opening $app_name for auto-update..."
				open -a "$app_name" --hide 2>/dev/null || true
				sleep 3
				((launched++)) || true
			else
				update_global_progress_info "catalog: updating $app_name via brew cask..."
				local brew_stdin=/dev/null
				{ true >/dev/tty; } 2>/dev/null && brew_stdin=/dev/tty
				brew install --cask "$token" --force <"$brew_stdin" 2>&1 | progress_pipe _parse_cask || true
				echo "$app_name" >>"${PROCESSED_APPS_FILE:-/dev/null}"
				((updated++)) || true
			fi
		done
	done

	append_progress_output "catalog: $updated updated, $launched launched, $skipped up to date/skipped, $not_found not in catalog"
	increment_global_progress
}

# ============================================================
# Layer 4 — Sparkle (SUFeedURL appcasts)
# ============================================================

# Decide a Sparkle update from an appcast piped on stdin. Args: local short
# version (CFBundleShortVersionString), local build (CFBundleVersion). Prints
# "<remote_ver>\t<dl_url>" when an update is available, nothing otherwise.
# Compares like-for-like — marketing version vs shortVersionString, or build vs
# sparkle:version — never a build number against a marketing string, which is
# what made the old "head -1 of the whole feed" logic misfire (e.g. comparing
# AppCleaner build 3804 against local 3.6.8, or grabbing a beta entry).
# ponytail: reads the FIRST <item> only; appcasts are newest-first by Sparkle
# convention. Switch to a max-version scan if a real feed ever violates that.
_sparkle_decide() {
	local l_short="$1" l_build="$2"
	local xml item r_short r_build dl_url local_ver remote_ver
	xml="$(cat)"
	# No `exit` after the first record: awk must drain stdin, otherwise printf
	# gets SIGPIPE and (under set -o pipefail) aborts this function on big feeds.
	item="$(printf '%s' "$xml" | awk 'BEGIN{RS="</item>"} NR==1{print}' || true)"

	r_short="$(printf '%s\n' "$item" | grep -o 'sparkle:shortVersionString="[^"]*"' | head -1 | sed 's/.*="//; s/"//' || true)"
	[[ -z "$r_short" ]] && r_short="$(printf '%s\n' "$item" | grep -o '<sparkle:shortVersionString>[^<]*' | head -1 | sed 's/.*>//' || true)"
	r_build="$(printf '%s\n' "$item" | grep -o 'sparkle:version="[^"]*"' | head -1 | sed 's/.*="//; s/"//' || true)"
	[[ -z "$r_build" ]] && r_build="$(printf '%s\n' "$item" | grep -o '<sparkle:version>[^<]*' | head -1 | sed 's/.*>//' || true)"
	dl_url="$(printf '%s\n' "$item" | grep -oE 'url="https://[^"]*\.(dmg|zip|pkg|tbz|tar\.[a-z]+)' | head -1 | sed 's/url="//' || true)"

	if [[ -n "$r_short" && -n "$l_short" ]]; then
		local_ver="$l_short"; remote_ver="$r_short"
	elif [[ -n "$r_build" && -n "$l_build" ]]; then
		local_ver="$l_build"; remote_ver="$r_build"
	else
		return 0
	fi
	[[ -z "$dl_url" ]] && return 0
	_version_outdated "$local_ver" "$remote_ver" || return 0
	printf '%s\t%s\n' "$remote_ver" "$dl_url"
}

update_sparkle_apps() {
	update_global_progress_info "sparkle: scanning..."
	increment_global_progress

	local updated=0 skipped=0
	local app_dir app_path app_name feed xml remote_ver local_ver local_build decision
	local slot manifest fetchlist

	SPARKLE_FEED_DIR="$(mktemp -d /tmp/raccoon-feeds-XXXXXX)"
	manifest="$SPARKLE_FEED_DIR/manifest.tsv"
	fetchlist="$SPARKLE_FEED_DIR/fetchlist"
	: >"$manifest"
	: >"$fetchlist"
	slot=0

	# Pass 1 — collect candidates. Local reads only, no network.
	# shellcheck disable=SC2046  # intentional word-split of the dir list
	for app_dir in $(_app_dirs); do
		[[ -d "$app_dir" ]] || continue
		for app_path in "$app_dir"/*.app; do
			[[ -d "$app_path" ]] || continue
			app_name="$(basename "$app_path" .app)"

			if grep -qx "$app_name" "${PROCESSED_APPS_FILE:-/dev/null}" 2>/dev/null; then
				continue
			fi

			feed="$(defaults read "$app_path/Contents/Info" SUFeedURL 2>/dev/null || true)"
			[[ -z "$feed" ]] && continue

			local_ver="$(defaults read "$app_path/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
			local_build="$(defaults read "$app_path/Contents/Info" CFBundleVersion 2>/dev/null || true)"

			slot=$((slot + 1))
			# app_path travels with the row: pass 3 opens the app, and by then
			# the loop that knew where it lives is long gone.
			printf '%s\t%s\t%s\t%s\t%s\n' "$slot" "$app_name" "$local_ver" "$local_build" "$app_path" >>"$manifest"
			printf '%s\0%s\0' "$feed" "$SPARKLE_FEED_DIR/$slot.xml" >>"$fetchlist"
		done
	done

	# Pass 2 — fetch every appcast at once. These are read-only GETs that change
	# nothing on disk, and done serially they dominated the command (~16s for 13
	# feeds). bash 3.2 has no `wait -n`, so xargs -P owns the concurrency cap.
	# ponytail: fixed cap; RCC_FETCH_JOBS is the knob if a slow link needs fewer.
	if [[ -s "$fetchlist" ]]; then
		update_global_progress_info "sparkle: fetching $slot feeds..."
		xargs -0 -P "${RCC_FETCH_JOBS:-8}" -n 2 \
			sh -c 'curl -fsSL --connect-timeout 5 --max-time 10 "$1" -o "$2" 2>/dev/null || true' _ \
			<"$fetchlist" || true
	fi

	# Pass 3 — compare and install. Strictly serial: this is the part that
	# replaces apps on disk, and it behaves exactly as it did before.
	while IFS=$'\t' read -r slot app_name local_ver local_build app_path; do
		[[ -n "$slot" ]] || continue
		xml="$(cat "$SPARKLE_FEED_DIR/$slot.xml" 2>/dev/null || true)"
		[[ -z "$xml" ]] && continue

		decision="$(printf '%s' "$xml" | _sparkle_decide "$local_ver" "$local_build")"
		if [[ -z "$decision" ]]; then
			((skipped++)) || true
			continue
		fi
		# _sparkle_decide still reports the enclosure URL — it is what proves the
		# item is a real update — but nothing downloads it any more.
		remote_ver="${decision%%$'\t'*}"

		if [[ "$RCC_DRY_RUN" == "true" ]]; then
			append_progress_output "sparkle: $app_name ${local_ver:-?} → $remote_ver"
			continue
		fi

		# A layer 4 app has SUFeedURL in its plist, which means Sparkle is built
		# into it: Sparkle swaps the bundle atomically and checks the EdDSA
		# signature, and a bash script can do neither. Opening the app hands the
		# update to the updater written for it.
		#
		# rcc used to download and install these itself, moving the old bundle
		# aside and copying the new one in with `|| true` on every line. When the
		# copy failed the app was already gone and a tick was printed anyway;
		# that is how Disk Drill was destroyed on 2026-06-25. Nothing in this
		# command writes to /Applications any more.
		# Seam, as with RACCOON_SSH in fleet.sh: the suites must be able to run
		# this path without launching anything.
		"${RCC_OPEN:-open}" -a "$app_path" 2>/dev/null || true
		append_progress_output "apps: ↗ $app_name (${local_ver:-?} → $remote_ver) — opened, its own updater will install"
		echo "$app_name" >>"${PROCESSED_APPS_FILE:-/dev/null}"
		((updated++)) || true
	done <"$manifest"

	append_progress_output "sparkle: $updated updated, $skipped up to date"
	increment_global_progress
}

# ============================================================
# Main
# ============================================================

_rcc_apps_cleanup() {
	stop_sudo_keepalive 2>/dev/null || true
	# CASK_CATALOG_FILE is the persistent ~/.raccoon cache now — deleting it here
	# would defeat the TTL and refetch 16MB on every run.
	[[ -n "${CASK_LOOKUP_FILE:-}" ]] && rm -f "$CASK_LOOKUP_FILE"
	[[ -n "${PROCESSED_APPS_FILE:-}" ]] && rm -f "$PROCESSED_APPS_FILE"
	[[ -n "${SPARKLE_FEED_DIR:-}" ]] && rm -rf "$SPARKLE_FEED_DIR"
	return 0
}

main() {
	if [[ "$RCC_DRY_RUN" == "true" ]]; then
		echo "${YELLOW}DRY RUN MODE - no changes made${NC}"
		echo ""
	fi

	trap _rcc_apps_cleanup EXIT

	# Cache sudo up front (Touch ID when available) so casks/pkgs that need root
	# complete without a prompt mid-progress (issue #23).
	#
	# /Applications used to be part of this gate, because the Sparkle path wrote
	# there and needed a primed timestamp. It no longer writes anywhere, so only
	# brew can still need root.
	if [[ "$RCC_DRY_RUN" != "true" ]] && command -v brew >/dev/null 2>&1; then
		if ensure_sudo; then
			start_sudo_keepalive
		else
			echo "${YELLOW}⚠ sudo unavailable — casks needing root may be skipped${NC}"
		fi
	fi

	# 2 slots per layer: mas, casks, catalog, sparkle.
	init_global_progress 8

	update_mas
	update_casks

	# Layer 3 — Homebrew catalog.
	if [[ "$RCC_NO_CATALOG" != "true" ]] && command -v brew >/dev/null 2>&1; then
		# The catalog is ~16MB and changes at most daily, so refetching it every
		# run is wasted bandwidth — worst exactly on the slow links where it
		# already hurts. `find -mtime +1` is the portable "older than a day"
		# test; bash 3.2 has no better one. Write via .tmp + mv so an
		# interrupted download can never leave a truncated cache behind.
		CASK_CATALOG_FILE="$HOME/.raccoon/cask-catalog.json"
		mkdir -p "$HOME/.raccoon" 2>/dev/null || true

		if [[ -s "$CASK_CATALOG_FILE" ]] && [[ -z "$(find "$CASK_CATALOG_FILE" -mtime +1 2>/dev/null)" ]]; then
			update_global_progress_info "catalog: using cache"
		else
			update_global_progress_info "catalog: downloading..."
			if curl -fsSL --connect-timeout 5 --max-time 30 "https://formulae.brew.sh/api/cask.json" -o "$CASK_CATALOG_FILE.tmp" 2>/dev/null; then
				mv -f "$CASK_CATALOG_FILE.tmp" "$CASK_CATALOG_FILE"
			else
				rm -f "$CASK_CATALOG_FILE.tmp"
			fi
		fi

		if [[ -s "$CASK_CATALOG_FILE" ]]; then
			PROCESSED_APPS_FILE="$(mktemp /tmp/raccoon-proc-XXXXXX)"
			CASK_LOOKUP_FILE=""
			update_homebrew_catalog
		else
			CASK_CATALOG_FILE=""
			append_progress_output "catalog: unavailable (no network)"
			increment_global_progress
			increment_global_progress
		fi
	else
		increment_global_progress
		increment_global_progress
	fi

	# Layer 4 — Sparkle.
	if [[ "$RCC_NO_SPARKLE" != "true" ]]; then
		PROCESSED_APPS_FILE="${PROCESSED_APPS_FILE:-$(mktemp /tmp/raccoon-proc-XXXXXX)}"
		update_sparkle_apps
	else
		increment_global_progress
		increment_global_progress
	fi

	finish_global_progress
	echo ""

	print_success "Completed"
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
	main "$@"
fi
