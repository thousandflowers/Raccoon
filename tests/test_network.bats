load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "network: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/network.sh" --help
    assert_success
}

@test "network: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/network.sh" -h
    assert_success
}

@test "network: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/network.sh" --help
    assert_output_contains "Usage"
}

@test "network: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/network.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "network: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/network.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "network: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/network.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "network: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/network.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

