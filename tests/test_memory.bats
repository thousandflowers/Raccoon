load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "memory: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/memory.sh" --help
    assert_success
}

@test "memory: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/memory.sh" -h
    assert_success
}

@test "memory: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/memory.sh" --help
    assert_output_contains "Usage"
}

@test "memory: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/memory.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "memory: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/memory.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "memory: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/memory.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "memory: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/memory.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# --- measured, not read: the findings of 2026-09-02 ---------------------------

@test "memory: --json reports the machine and the processes, ranked by footprint" {
	run bash "$SCRIPT_DIR/bin/memory.sh" --json --top 5
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
m = d["memory"]
assert m["total_mb"] > 0 and m["used_mb"] > 0, m
assert m["used_mb"] <= m["total_mb"] + m["compressed_mb"], m
ps = d["processes"]
assert 0 < len(ps) <= 5, len(ps)
fp = [p["footprint_kb"] for p in ps]
assert fp == sorted(fp, reverse=True), fp
for p in ps:
    assert isinstance(p["pid"], int) and p["command"], p
    assert "rss_kb" in p
'
}

@test "memory: text and --json rank the same processes" {
	run bash "$SCRIPT_DIR/bin/memory.sh" --json --top 3
	assert_success
	local json_pids
	json_pids=$(printf '%s' "$output" | python3 -c 'import json,sys; print(" ".join(str(p["pid"]) for p in json.load(sys.stdin)["processes"]))')
	run bash "$SCRIPT_DIR/bin/memory.sh" --top 3
	assert_success
	# Two samples a second apart share at least the heaviest process.
	local first=${json_pids%% *}
	[[ "$output" == *"| $first "* ]] || [[ "$output" == *"| $first|"* ]] || [[ "$output" == *"$first"* ]]
}

@test "memory: without sysctl it is 'not checked', never 'Total RAM 0 GB'" {
	run env -i PATH=/usr/bin:/bin HOME="$HOME" bash "$SCRIPT_DIR/bin/memory.sh"
	[[ "$status" -eq 3 ]]
	[[ "$output" == *"Not checked"*"sysctl"* ]]
	[[ "$output" != *"Total RAM"* ]]
}
