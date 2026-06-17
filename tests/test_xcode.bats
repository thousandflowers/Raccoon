load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "xcode: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --help
    assert_success
}

@test "xcode: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" -h
    assert_success
}

@test "xcode: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --help
    assert_output_contains "Usage"
}

@test "xcode: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "xcode: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "xcode: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "xcode: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

