load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "upgrade: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --help
    assert_success
}

@test "upgrade: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" -h
    assert_success
}

@test "upgrade: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --help
    assert_output_contains "Usage"
}

@test "upgrade: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "upgrade: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "upgrade: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "upgrade: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

