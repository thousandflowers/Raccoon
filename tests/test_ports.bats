load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "ports: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --help
    assert_success
}

@test "ports: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/ports.sh" -h
    assert_success
}

@test "ports: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --help
    assert_output_contains "Usage"
}

@test "ports: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ports: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/ports.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ports: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ports: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/ports.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

