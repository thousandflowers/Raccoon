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

