#!/usr/bin/env bats
# Tests for the multi-layer apps engine: catalog helpers, version compare, the
# Homebrew-catalog and Sparkle layers. No network, no real brew/mas — synthetic
# catalog JSON, synthetic .app bundles (via `defaults`), and file:// appcasts.
# A non-brew token ("raccoon-test-app") avoids the brew-already-installed skip.

load test_helper

setup() {
	setup_raccoon_env
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/bin/apps.sh"   # guarded: main() does not run when sourced

	CATALOG="$HOME/cask.json"
	cat > "$CATALOG" <<'JSON'
{"token":"google-chrome","version":"149.0.7827.197","auto_updates":true,"app":["Google Chrome.app"]}
{"token":"iterm2","version":"3.6.0","auto_updates":false,"app":["iTerm.app"]}
{"token":"rectangle","version":"0.9.0","auto_updates":false,"app":["Rectangle.app"]}
{"token":"vlc","version":"3.0.20","auto_updates":false,"app":["VLC.app"]}
{"token":"raccoon-test-app","version":"2.0.0","auto_updates":false,"app":["RaccoonTestApp.app"]}
{"token":"raccoon-auto","version":"2.0.0","auto_updates":true,"app":["RaccoonAuto.app"]}
{"token":"oldcask","version":"1.0","deprecated":true,"app":["Old.app"]}
{"token":"multiver","version":"5.0.0","auto_updates":false,"app":["MultiVer.app"],"variations":{"sequoia":{"version":"4.0.0"}}}
{"token":"pkgapp","version":"3.0.0","auto_updates":false,"name":["PkgApp"],"pkg":["PkgApp.pkg"]}
JSON

	CASK_CATALOG_FILE="$CATALOG"
	CASK_LOOKUP_FILE="$HOME/lookup.tsv"
	APPDIR="$HOME/testapps"
	mkdir -p "$APPDIR"
	export RCC_APP_DIRS="$APPDIR"
	PROCESSED_APPS_FILE="$HOME/processed.txt"
	: > "$PROCESSED_APPS_FILE"
}

teardown() {
	teardown_raccoon_env
}

# Create $APPDIR/<name>.app with a version (and optional SUFeedURL).
_make_app() {
	local name="$1" ver="$2" feed="${3:-}"
	mkdir -p "$APPDIR/$name.app/Contents"
	defaults write "$APPDIR/$name.app/Contents/Info" CFBundleShortVersionString -string "$ver" >/dev/null 2>&1
	[[ -n "$feed" ]] && defaults write "$APPDIR/$name.app/Contents/Info" SUFeedURL -string "$feed" >/dev/null 2>&1
	return 0
}

# --- catalog helpers ---------------------------------------------------------
@test "_build_cask_lookup parses tokens, apps, versions, auto flag" {
	_build_cask_lookup
	grep -q "$(printf 'iterm2\tiTerm.app\t3.6.0\t0')" "$CASK_LOOKUP_FILE"
}

@test "_build_cask_lookup picks the top-level version, not a variations fallback" {
	_build_cask_lookup
	grep -q "$(printf 'multiver\tMultiVer.app\t5.0.0\t0')" "$CASK_LOOKUP_FILE"
}

@test "_lookup_app finds an app by name" {
	_build_cask_lookup
	run _lookup_app "iTerm.app"
	assert_output_contains "iterm2"
}

@test "pkg/installer cask (no app artifact) is matched via its display name" {
	_build_cask_lookup
	run _lookup_app "PkgApp.app"
	assert_output_contains "pkgapp"
}

@test "pkg-cask app is reported outdated in catalog dry-run" {
	_make_app "PkgApp" "1.0.0"
	RCC_DRY_RUN=true
	run update_homebrew_catalog
	assert_success
	assert_output_contains "PkgApp 1.0.0 → 3.0.0"
}

@test "_lookup_app returns empty for an unknown app" {
	_build_cask_lookup
	run _lookup_app "NotExisting.app"
	[[ -z "$output" ]]
}

@test "deprecated casks are excluded from the lookup" {
	_build_cask_lookup
	run _lookup_app "Old.app"
	[[ -z "$output" ]]
}

# --- version compare ---------------------------------------------------------
@test "_version_outdated: older local is outdated" {
	run _version_outdated "3.5.0" "3.6.0"
	[[ "$status" -eq 0 ]]
}

@test "_version_outdated: equal is not outdated" {
	run _version_outdated "3.6.0" "3.6.0"
	[[ "$status" -eq 1 ]]
}

@test "_version_outdated: newer local is not outdated" {
	run _version_outdated "3.6.1" "3.6.0"
	[[ "$status" -eq 1 ]]
}

# --- layer 3: Homebrew catalog ----------------------------------------------
@test "catalog dry-run reports an outdated app with its versions" {
	_make_app "RaccoonTestApp" "1.0.0"
	RCC_DRY_RUN=true
	run update_homebrew_catalog
	assert_success
	assert_output_contains "RaccoonTestApp"
	assert_output_contains "1.0.0"
	assert_output_contains "2.0.0"
}

@test "catalog dry-run updates an auto-updater app via brew by default" {
	_make_app "RaccoonAuto" "1.0.0"
	RCC_DRY_RUN=true
	run update_homebrew_catalog
	assert_success
	assert_output_contains "RaccoonAuto 1.0.0 → 2.0.0"
	[[ "$output" != *"auto-updater"* ]]
}

@test "catalog dry-run with --auto-launch opens the auto-updater app instead" {
	_make_app "RaccoonAuto" "1.0.0"
	RCC_DRY_RUN=true RCC_AUTO_LAUNCH=true
	run update_homebrew_catalog
	assert_success
	assert_output_contains "auto-updater"
}

@test "catalog: up-to-date app is not reported as an update" {
	_make_app "RaccoonTestApp" "2.0.0"
	RCC_DRY_RUN=true
	run update_homebrew_catalog
	assert_success
	[[ "$output" != *"RaccoonTestApp 2.0.0 → "* ]]
}

# --- layer 4: Sparkle --------------------------------------------------------
@test "sparkle dry-run reports an outdated app from a file:// appcast" {
	cat > "$HOME/appcast.xml" <<'XML'
<rss><channel><item>
<sparkle:shortVersionString>2.0.0</sparkle:shortVersionString>
<enclosure url="https://example.com/App.dmg"/>
</item></channel></rss>
XML
	_make_app "SparkleApp" "1.0.0" "file://$HOME/appcast.xml"
	RCC_DRY_RUN=true
	run update_sparkle_apps
	assert_success
	assert_output_contains "SparkleApp"
	assert_output_contains "2.0.0"
}

@test "sparkle: app without SUFeedURL is skipped, exit 0" {
	_make_app "NoFeedApp" "1.0.0"
	RCC_DRY_RUN=true
	run update_sparkle_apps
	assert_success
	[[ "$output" != *"NoFeedApp"* ]]
}

@test "sparkle: unreachable feed is skipped, exit 0" {
	_make_app "DeadFeedApp" "1.0.0" "file://$HOME/does-not-exist.xml"
	RCC_DRY_RUN=true
	run update_sparkle_apps
	assert_success
	[[ "$output" != *"DeadFeedApp"* ]]
}

@test "sparkle: already-processed app is skipped" {
	cat > "$HOME/appcast.xml" <<'XML'
<rss><channel><item>
<sparkle:shortVersionString>2.0.0</sparkle:shortVersionString>
<enclosure url="https://example.com/App.dmg"/>
</item></channel></rss>
XML
	_make_app "SparkleApp" "1.0.0" "file://$HOME/appcast.xml"
	echo "SparkleApp" > "$PROCESSED_APPS_FILE"
	RCC_DRY_RUN=true
	run update_sparkle_apps
	assert_success
	[[ "$output" != *"SparkleApp 1.0.0"* ]]
}

# --- help --------------------------------------------------------------------
@test "apps --help lists the four layers" {
	# sourcing apps.sh in setup() reassigns SCRIPT_DIR, so use the bats dir.
	run bash "$BATS_TEST_DIRNAME/../bin/apps.sh" --help
	assert_success
	assert_output_contains "Homebrew catalog"
	assert_output_contains "--no-catalog"
	assert_output_contains "--auto-launch"
}
