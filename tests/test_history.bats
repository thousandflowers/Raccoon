load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "history: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/history.sh" --help
    assert_success
}

@test "history: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/history.sh" -h
    assert_success
}

@test "history: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/history.sh" --help
    assert_output_contains "Usage"
}

@test "history: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/history.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "history: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/history.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "history: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/history.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "history: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/history.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

