load test_helper

setup() {
	setup_raccoon_env
}

# --- count_lines helper ---

@test "count_lines: returns 0 on empty input" {
	source "$SCRIPT_DIR/bin/audit.sh"
	result="$(printf '' | count_lines)"
	[[ "$result" == "0" ]]
}

@test "count_lines: counts single line" {
	source "$SCRIPT_DIR/bin/audit.sh"
	result="$(printf 'hello\n' | count_lines)"
	[[ "$result" == "1" ]]
}

@test "count_lines: counts multiple lines" {
	source "$SCRIPT_DIR/bin/audit.sh"
	result="$(printf 'a\nb\nc\n' | count_lines)"
	[[ "$result" == "3" ]]
}

@test "count_lines: strips leading whitespace from wc output" {
	source "$SCRIPT_DIR/bin/audit.sh"
	# wc -l outputs leading spaces like "      10" for alignment
	# count_lines should strip them so the result is a clean number
	result="$(printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nl\n' | count_lines)"
	[[ "$result" == "10" ]]
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
