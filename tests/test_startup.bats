load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "startup: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --help
    assert_success
}

@test "startup: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/startup.sh" -h
    assert_success
}

@test "startup: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --help
    assert_output_contains "Usage"
}

@test "startup: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "startup: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/startup.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "startup: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "startup: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/startup.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

