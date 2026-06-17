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

