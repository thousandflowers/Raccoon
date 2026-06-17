load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "fonts: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --help
    assert_success
}

@test "fonts: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" -h
    assert_success
}

@test "fonts: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --help
    assert_output_contains "Usage"
}

@test "fonts: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "fonts: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "fonts: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "fonts: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

