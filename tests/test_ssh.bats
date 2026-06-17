load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "ssh: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/ssh.sh" --help
    assert_success
}

@test "ssh: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/ssh.sh" -h
    assert_success
}

@test "ssh: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/ssh.sh" --help
    assert_output_contains "Usage"
}

@test "ssh: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/ssh.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ssh: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/ssh.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ssh: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/ssh.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ssh: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/ssh.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

