#!/usr/bin/env bats
# Tests for report secret-redaction: on by default, disabled with --no-redact.
# Redaction happens once, at the AUDIT_RESULTS choke point (_redact_audit_results
# in lib/core/report.sh), so it is deterministic and needs no real system state.

load test_helper

setup() {
	setup_raccoon_env
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/lib/core/report.sh"
	AUDIT_RESULTS=(
		"fail"$'\t'"Network"$'\t'"Wi-Fi Password: hunter2secret"
		"warn"$'\t'"Network"$'\t'"Gateway: 192.168.1.1 at 3c:22:fb:aa:bb:cc"
		"pass"$'\t'"SSH"$'\t'"SSH Keys: 3 key(s)"
		"pass"$'\t'"System"$'\t'"macOS: 15.2 (24C101)"
	)
}

teardown() {
	teardown_raccoon_env
}

@test "redact: default scrubs a Wi-Fi password from the array" {
	_redact_audit_results
	printf '%s\n' "${AUDIT_RESULTS[@]}" > "$BATS_TEST_TMPDIR/out"
	run cat "$BATS_TEST_TMPDIR/out"
	[[ "$output" != *"hunter2secret"* ]]
	[[ "$output" == *"Wi-Fi Password: [redacted]"* ]]
}

@test "redact: --no-redact (RCC_REDACT=0) keeps the Wi-Fi password verbatim" {
	RCC_REDACT=0
	_redact_audit_results
	printf '%s\n' "${AUDIT_RESULTS[@]}" > "$BATS_TEST_TMPDIR/out"
	run cat "$BATS_TEST_TMPDIR/out"
	[[ "$output" == *"Wi-Fi Password: hunter2secret"* ]]
}

@test "redact: default scrubs IPv4 and MAC addresses" {
	_redact_audit_results
	printf '%s\n' "${AUDIT_RESULTS[@]}" > "$BATS_TEST_TMPDIR/out"
	run cat "$BATS_TEST_TMPDIR/out"
	[[ "$output" != *"192.168.1.1"* ]]
	[[ "$output" != *"3c:22:fb:aa:bb:cc"* ]]
	[[ "$output" == *"[redacted-ip]"* ]]
	[[ "$output" == *"[redacted-mac]"* ]]
}

@test "redact: non-secret values are left intact" {
	_redact_audit_results
	printf '%s\n' "${AUDIT_RESULTS[@]}" > "$BATS_TEST_TMPDIR/out"
	run cat "$BATS_TEST_TMPDIR/out"
	# a count and a version string must survive redaction unchanged
	[[ "$output" == *"SSH Keys: 3 key(s)"* ]]
	[[ "$output" == *"macOS: 15.2 (24C101)"* ]]
}

@test "redact: the rendered Markdown report contains no Wi-Fi password by default" {
	REPORT_DATE="2026-01-01 00:00:00"
	_redact_audit_results
	run render_report_md
	assert_success
	[[ "$output" != *"hunter2secret"* ]]
	[[ "$output" == *"[redacted]"* ]]
}

@test "redact: --no-redact lets the Wi-Fi password reach the Markdown report" {
	REPORT_DATE="2026-01-01 00:00:00"
	RCC_REDACT=0
	_redact_audit_results
	run render_report_md
	assert_success
	[[ "$output" == *"hunter2secret"* ]]
}
