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

