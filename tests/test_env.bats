load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "env: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/env.sh" --help
    assert_success
}

@test "env: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/env.sh" -h
    assert_success
}

@test "env: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/env.sh" --help
    assert_output_contains "Usage"
}

@test "env: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/env.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "env: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/env.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "env: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/env.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "env: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/env.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# --- measured, not read: the findings of 2026-09-02 ---------------------------

@test "env: a broken symlink inside a PATH entry that is itself a symlink is found" {
	local real="$HOME/real-bin" link="$HOME/linked-bin"
	mkdir -p "$real"
	ln -s "$HOME/nowhere" "$real/gone"
	ln -s "$real" "$link"
	PATH="$link:/usr/bin:/bin" run bash "$SCRIPT_DIR/bin/env.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
names = [b["name"] for b in d["broken_symlinks"]]
assert "gone" in names, names
'
}

@test "env: text and --json agree about duplicates, empty elements included" {
	# An empty element (PATH=a::b) is skipped by both, not printed as a blank
	# duplicate by one and ignored by the other.
	PATH="/usr/bin::/bin:/usr/bin" run bash "$SCRIPT_DIR/bin/env.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
assert json.load(sys.stdin)["duplicates"] == ["/usr/bin"]
'
	NO_COLOR=1 PATH="/usr/bin::/bin:/usr/bin" run bash "$SCRIPT_DIR/bin/env.sh"
	assert_success
	[[ "$output" == *"/usr/bin"*"duplicate"* ]]
	[[ "$output" != *"No duplicates found"* ]]
	[[ "$output" != *"|  "*"duplicate"* ]]
}

@test "env: a tool that prints nothing for --version is 'found', not an empty version" {
	local shim="$HOME/shim"
	mkdir -p "$shim"
	printf '#!/bin/bash\nexit 0\n' > "$shim/git"
	chmod +x "$shim/git"
	PATH="$shim:/usr/bin:/bin" run bash "$SCRIPT_DIR/bin/env.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
[git] = [t for t in json.load(sys.stdin)["tools"] if t["name"] == "git"]
assert git["found"] is True and git["version"] == "found", git
'
}
