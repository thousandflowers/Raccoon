#!/usr/bin/env bats
# Tests for `rcc wifi`. These run in CI where there may be no Wi-Fi interface,
# so they only assert graceful behaviour (exit 0, valid shapes), not content.

load test_helper

setup() {
	setup_raccoon_env
}

teardown() {
	teardown_raccoon_env
}

@test "wifi exits 0 with no arguments" {
	run bash "$SCRIPT_DIR/bin/wifi.sh"
	assert_success
}

@test "wifi --json output starts with {" {
	run bash "$SCRIPT_DIR/bin/wifi.sh" --json
	assert_success
	[[ "$output" == '{'* ]]
}

@test "wifi --active exits 0" {
	run bash "$SCRIPT_DIR/bin/wifi.sh" --active
	assert_success
}

@test "wifi --known exits 0" {
	run bash "$SCRIPT_DIR/bin/wifi.sh" --known
	assert_success
}

@test "wifi --help shows usage and exits 0" {
	run bash "$SCRIPT_DIR/bin/wifi.sh" --help
	assert_success
	assert_output_contains "Usage: rcc wifi"
}

@test "wifi with non-tty stdin and no flags does not block on the password prompt" {
	# bats stdin is not a tty, so section_passwords must skip silently.
	run bash "$SCRIPT_DIR/bin/wifi.sh"
	assert_success
	[[ "$output" != *"Mostrare le password"* ]]
}
