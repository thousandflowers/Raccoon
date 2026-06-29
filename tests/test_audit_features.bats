load test_helper

setup() {
	setup_raccoon_env
}

# --- semantic exit codes (issue #39) ---

@test "_audit_exit_code: 0 when all pass" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=5 WARN_count=0 FAIL_count=0
	run _audit_exit_code
	[[ "$output" == "0" ]]
}

@test "_audit_exit_code: 2 when warnings only" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=5 WARN_count=3 FAIL_count=0
	run _audit_exit_code
	[[ "$output" == "2" ]]
}

@test "_audit_exit_code: 1 when any failure (dominates warnings)" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=5 WARN_count=3 FAIL_count=1
	run _audit_exit_code
	[[ "$output" == "1" ]]
}

# --- check groups / --only / --list-checks (issue #38) ---

@test "_resolve_groups: empty selects all groups in order" {
	source "$SCRIPT_DIR/bin/audit.sh"
	ONLY_GROUPS=""
	_resolve_groups
	[[ "${SELECTED_GROUPS[*]}" == "core network auth persistence privacy additional" ]]
}

@test "_resolve_groups: a subset is honored and order-preserving" {
	source "$SCRIPT_DIR/bin/audit.sh"
	ONLY_GROUPS="network,core"
	_resolve_groups
	[[ "${SELECTED_GROUPS[*]}" == "network core" ]]
}

@test "_resolve_groups: unknown group exits 2" {
	run bash -c "source '$SCRIPT_DIR/bin/audit.sh'; ONLY_GROUPS=bogus; _resolve_groups"
	[[ "$status" -eq 2 ]]
}

@test "audit.sh: --list-checks exits 0 and lists groups" {
	run bash "$SCRIPT_DIR/bin/audit.sh" --list-checks
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"core"* ]]
	[[ "$output" == *"network"* ]]
}

# --- CIS mapping (issue #33, CIS-only) ---

@test "_check_cis: maps a covered check, blank for an uncovered one" {
	source "$SCRIPT_DIR/bin/audit.sh"
	[[ "$(_check_cis FileVault)" == *"FileVault"* ]]
	[[ -z "$(_check_cis "Open Ports")" ]]
	[[ -z "$(_check_cis "Nonexistent Check")" ]]
}

# --- command table / --verbose (issue #35) ---

@test "_check_command: maps a check to its probe, blank for unknown" {
	source "$SCRIPT_DIR/bin/audit.sh"
	[[ "$(_check_command FileVault)" == *"fdesetup status"* ]]
	[[ -z "$(_check_command "Nonexistent Check")" ]]
}

@test "_redact: masks an obvious secret" {
	source "$SCRIPT_DIR/bin/audit.sh"
	result="$(printf 'password = hunter2\nok line\n' | _redact)"
	[[ "$result" != *"hunter2"* ]]
	[[ "$result" == *"ok line"* ]]
}

# --- JSON gains cis + command fields (issues #33/#35) ---

@test "print_output_json: includes cis and command fields" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=1 WARN_count=0 FAIL_count=0 DEEP_SCAN=false
	AUDIT_RESULTS=("pass"$'\t'"Core Security"$'\t'"FileVault: Enabled")
	result="$(print_output_json)"
	[[ "$result" == *'"cis":'* ]]
	[[ "$result" == *'"command":'* ]]
	[[ "$result" == *'fdesetup status'* ]]
}

# --- auditor-ready HTML report (issue #34) ---

@test "print_output_html: identity header, per-check row, CIS + verify command" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=1 WARN_count=0 FAIL_count=0 DEEP_SCAN=false
	AUDIT_RESULTS=("pass"$'\t'"Core Security"$'\t'"FileVault: Enabled")
	result="$(print_output_html)"
	[[ "$result" == *"<!DOCTYPE html>"* ]]
	[[ "$result" == *"Host"* ]]
	[[ "$result" == *"FileVault"* ]]
	[[ "$result" == *"2.5.1.1"* ]]
	[[ "$result" == *"fdesetup status"* ]]
	[[ "$result" == *"</html>"* ]]
}

@test "_html_escape: escapes angle brackets and ampersands" {
	source "$SCRIPT_DIR/bin/audit.sh"
	[[ "$(_html_escape '<a> & "b"')" == "&lt;a&gt; &amp; &quot;b&quot;" ]]
}
