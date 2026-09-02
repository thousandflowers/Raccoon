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

# --- measured, not read: the findings of 2026-09-02 ---------------------------

@test "wifi --json says whether the link is up, apart from whether the name is known" {
	run bash "$SCRIPT_DIR/bin/wifi.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert isinstance(d["connected"], bool)
assert isinstance(d["ssid_hidden"], bool)
# The name can only be hidden on a link that is up.
assert not (d["ssid_hidden"] and not d["connected"])
assert not (d["ssid_hidden"] and d["active_ssid"])
'
}

@test "wifi without /usr/sbin is 'not checked', not 'Not connected' with no networks" {
	# networksetup and ipconfig live in /usr/sbin. The old script answered
	# "en0", "Not connected" and "No saved networks" with exit 0 without them.
	run env -i PATH=/usr/bin:/bin HOME="$HOME" bash "$SCRIPT_DIR/bin/wifi.sh" --json
	[[ "$status" -eq 3 ]]
	[[ "$output" == *"Not checked"* ]]
	[[ "$output" != *'"known_networks"'* ]]
}

@test "wifi text mode does not print 'Not connected' while the link is up" {
	run bash "$SCRIPT_DIR/bin/wifi.sh" --json
	assert_success
	local up
	up=$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["connected"])')
	run bash "$SCRIPT_DIR/bin/wifi.sh" --active
	assert_success
	if [[ "$up" == "True" ]]; then
		[[ "$output" != *"Not connected"* ]]
	else
		# A Mac with no Wi-Fi port (a CI runner) says so; one with a port that
		# is idle says "Not connected". Neither is the other's answer.
		[[ "$output" == *"Not connected"* || "$output" == *"No Wi-Fi interface"* ]]
	fi
}
