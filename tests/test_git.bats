load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "git: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/git.sh" --help
    assert_success
}

@test "git: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/git.sh" -h
    assert_success
}

@test "git: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/git.sh" --help
    assert_output_contains "Usage"
}

@test "git: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/git.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/git.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/git.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/git.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# A Mac with no git repositories under HOME crashed here with
# "repos[@]: unbound variable": in bash 3.2 an empty array under set -u is an
# error, not an empty list, and the "No repositories found" branch sat after
# the loop that died.
@test "git: a machine with no repositories says so instead of crashing" {
	local empty
	empty="$(mktemp -d)"
	run env HOME="$empty" bash "$SCRIPT_DIR/bin/git.sh"
	rmdir "$empty" 2>/dev/null || true
	assert_success
	assert_output_contains "No repositories found"
	[[ "$output" != *"unbound variable"* ]] || {
		echo "still crashing: $output" >&2
		false
	}
}
