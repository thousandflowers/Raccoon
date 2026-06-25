load test_helper

setup() {
	setup_raccoon_env
}

# --- save_to_history rotation ---

@test "save_to_history: rotation keeps at most 30 files" {
	source "$SCRIPT_DIR/bin/audit.sh"

	# Use a temp dir so we don't touch real history
	local tmpdir
	tmpdir="$(mktemp -d)"
	HISTORY_DIR="$tmpdir"
	PASS_count=0 WARN_count=0 FAIL_count=0 DEEP_SCAN=false

	# Create 35 audit files
	for i in $(seq 1 35); do
		timestamp="2025-01-01_$(printf '%02d' $((i % 24))):00:00"
		touch "$tmpdir/audit_${timestamp}.json"
	done

	save_to_history

	# Now count files — should be 31 (30 old + 1 new)
	local count
	count="$(ls "$tmpdir"/audit_*.json 2>/dev/null | wc -l | tr -d ' ')"
	[[ "$count" -le 31 ]]

	rm -rf "$tmpdir"
}

# --- help / error paths ---

@test "audit.sh: show_audit_help exits cleanly" {
	source "$SCRIPT_DIR/bin/audit.sh"
	run show_audit_help
	[[ "$status" -eq 0 ]]
}

@test "audit.sh: print_summary with zero counts" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=0 WARN_count=0 FAIL_count=0
	run print_summary
	[[ "$status" -eq 0 ]]
}

@test "audit.sh: print_summary with mixed counts" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=10 WARN_count=2 FAIL_count=1
	run print_summary
	[[ "$status" -eq 0 ]]
}

# --- JSON output ---

@test "audit.sh: print_output_json produces valid JSON shell" {
	source "$SCRIPT_DIR/bin/audit.sh"
	PASS_count=5 WARN_count=1 FAIL_count=0 DEEP_SCAN=false
	result="$(print_output_json 2>&1)"
	[[ "$result" == *'"pass": 5'* ]]
	[[ "$result" == *'"warning": 1'* ]]
	[[ "$result" == *'"fail": 0'* ]]
}

# --- report rendering (regression: ragged boxes) ---

@test "audit.sh: report box rows all align to one width" {
	run bash -c "bash '$SCRIPT_DIR/bin/audit.sh' 2>/dev/null | bash '$SCRIPT_DIR/tests/check_box_width.sh'"
	assert_output_contains "OK"
}

@test "audit.sh: _box_row pads to the border width" {
	source "$SCRIPT_DIR/bin/audit.sh"
	border="$(_box_border)"
	row="$(_box_row "x hi" "x hi")"
	[[ "${#border}" -eq "${#row}" ]]
}
