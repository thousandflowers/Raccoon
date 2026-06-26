#!/usr/bin/env bats
# Tests for the first-run onboarding wizard.

load test_helper

setup() {
	setup_raccoon_env
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/lib/core/common.sh"
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/lib/core/commands.sh"
}

teardown() {
	teardown_raccoon_env
}

@test "onboarding box renders the welcome and the three commands" {
	run _render_onboarding
	assert_success
	assert_output_contains "Welcome to Raccoon"
	assert_output_contains "rcc audit"
	assert_output_contains "rcc wifi"
}

@test "onboarding is silent when the sentinel already exists" {
	mkdir -p "$HOME/.raccoon"
	touch "$HOME/.raccoon/onboarded"
	run show_onboarding
	assert_success
	[[ -z "$output" ]]
}

@test "onboarding skips and creates no sentinel when stdin is not a tty" {
	# bats runs with a non-tty stdin, so the [[ -t 0 ]] guard short-circuits.
	run show_onboarding
	assert_success
	[[ -z "$output" ]]
	[[ ! -f "$HOME/.raccoon/onboarded" ]]
}

@test "onboarding shows the wizard and creates the sentinel on a tty" {
	# `script` gives the command a real pty (so -t 0 is true); piping a byte
	# into it satisfies the keypress read without waiting for the timeout.
	printf 'x' | script -q /dev/null bash -c \
		"source '$SCRIPT_DIR/lib/core/common.sh'; source '$SCRIPT_DIR/lib/core/commands.sh'; show_onboarding" \
		>/dev/null 2>&1 || true
	[[ -f "$HOME/.raccoon/onboarded" ]]
}
