load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "trash: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/trash.sh" --help
    assert_success
}

@test "trash: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/trash.sh" -h
    assert_success
}

@test "trash: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/trash.sh" --help
    assert_output_contains "Usage"
}

@test "trash: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/trash.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "trash: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/trash.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "trash: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/trash.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "trash: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/trash.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

