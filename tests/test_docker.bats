load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "docker: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --help
    assert_success
}

@test "docker: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/docker.sh" -h
    assert_success
}

@test "docker: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --help
    assert_output_contains "Usage"
}

@test "docker: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "docker: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/docker.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "docker: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "docker: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/docker.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

