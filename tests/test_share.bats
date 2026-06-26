#!/usr/bin/env bats
# Tests for `rcc audit --share` (anonymous GitHub Gist). curl is mocked via
# RACCOON_CURL so nothing hits the network.

load test_helper

setup() {
	setup_raccoon_env
	# A curl mock that produces no output -> simulates "no connection".
	cat > "$HOME/mockcurl" <<'MOCK'
#!/bin/bash
exit 0
MOCK
	chmod +x "$HOME/mockcurl"
}

teardown() {
	teardown_raccoon_env
}

@test "audit --share with an unreachable API reports unavailable and exits 0" {
	RACCOON_CURL="$HOME/mockcurl" run bash "$SCRIPT_DIR/bin/audit.sh" --share
	assert_success
	assert_output_contains "Sharing unavailable"
}

@test "audit --share with --quiet is ignored with a warning" {
	run bash "$SCRIPT_DIR/bin/audit.sh" --share --quiet
	assert_success
	assert_output_contains "ignored"
}

@test "_share_payload builds a valid gist payload with the report file" {
	run bash -c "
		source '$SCRIPT_DIR/bin/audit.sh'
		AUDIT_RESULTS=()
		AUDIT_RESULTS+=(\"pass\$(printf '\\t')Core Security\$(printf '\\t')FileVault: Enabled\")
		_share_payload
	"
	assert_success
	assert_output_contains "raccoon-audit.md"
	assert_output_contains '"public":true'
}
