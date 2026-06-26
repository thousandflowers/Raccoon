#!/usr/bin/env bats
# Tests for the audit health-history sparkline in the menu banner.

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

@test "health history is empty when there is no audit history" {
	run show_health_history
	assert_success
	[[ -z "$output" ]]
}

@test "health history is empty with fewer than two audits" {
	mkdir -p "$HOME/.raccoon/audit-history"
	echo '{"fail": 0}' > "$HOME/.raccoon/audit-history/audit_2026-01-01_09:00:00.json"
	run show_health_history
	assert_success
	[[ -z "$output" ]]
}

@test "health history renders dots and a counter for >=2 audits" {
	local d="$HOME/.raccoon/audit-history"
	mkdir -p "$d"
	echo '{"fail": 0}' > "$d/audit_2026-01-01_09:00:00.json"
	echo '{"fail": 0}' > "$d/audit_2026-01-02_09:00:00.json"
	echo '{"fail": 2}' > "$d/audit_2026-01-03_09:00:00.json"
	run show_health_history
	assert_success
	assert_output_contains "Last audits"
	assert_output_contains "●"
	assert_output_contains "○"
	assert_output_contains "2/3"
}
