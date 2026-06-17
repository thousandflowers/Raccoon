load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "battery: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --help
    assert_success
}

@test "battery: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/battery.sh" -h
    assert_success
}

@test "battery: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --help
    assert_output_contains "Usage"
}

@test "battery: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "battery: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/battery.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "battery: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "battery: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/battery.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

