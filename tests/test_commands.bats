#!/usr/bin/env bats

load test_helper

setup() {
	# shellcheck source=../lib/core/common.sh
	setup_raccoon_env
	source "$SCRIPT_DIR/lib/core/common.sh"
	source "$SCRIPT_DIR/lib/core/commands.sh"
}

teardown() {
	teardown_raccoon_env
}

@test "VERSION is set" {
	[[ -n "$VERSION" ]]
}

@test "TAGLINE is set" {
	[[ -n "$TAGLINE" ]]
}

@test "MENU_ITEMS is not empty" {
	[[ ${#MENU_ITEMS[@]} -gt 0 ]]
}

@test "TOTAL_OPTIONS matches MENU_ITEMS count" {
	local non_separator=0
	for item in "${MENU_ITEMS[@]}"; do
		[[ "$item" != "---" ]] && ((non_separator++))
	done
	[[ $non_separator -le $TOTAL_OPTIONS ]]
}

@test "show_version prints Raccoon version" {
	run show_version
	assert_success
	assert_output_contains "Raccoon version"
}

@test "reset_terminal does not error" {
	run reset_terminal
	assert_success
}
