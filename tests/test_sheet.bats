#!/usr/bin/env bats
# Tests for the intervention sheet (rcc audit --sheet / --hours / --notes).

load test_helper

setup() {
	setup_raccoon_env
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/lib/core/common.sh"
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/lib/core/report.sh"
}

teardown() {
	teardown_raccoon_env
}

@test "render_intervention_sheet renders the sheet from synthetic results" {
	AUDIT_RESULTS=()
	AUDIT_RESULTS+=("pass"$'\t'"Core Security"$'\t'"FileVault: Enabled")
	AUDIT_RESULTS+=("fail"$'\t'"Core Security"$'\t'"Firewall: Disabled")
	run render_intervention_sheet
	assert_success
	assert_output_contains "Scheda Intervento"
	assert_output_contains "Generato da Raccoon"
	assert_output_contains "Firewall"
}

@test "audit --sheet exits 0" {
	run bash "$SCRIPT_DIR/bin/audit.sh" --sheet
	assert_success
	assert_output_contains "Scheda Intervento"
}

@test "audit --sheet --rtf produces valid RTF" {
	run bash "$SCRIPT_DIR/bin/audit.sh" --sheet --rtf
	assert_success
	[[ "$output" == '{\rtf'* ]]
}

@test "audit --hours 3 --sheet includes the hours" {
	run bash "$SCRIPT_DIR/bin/audit.sh" --hours 3 --sheet
	assert_success
	assert_output_contains "3"
}
