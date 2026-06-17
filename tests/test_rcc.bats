load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "rcc: --version prints version" {
    run bash "$SCRIPT_DIR/rcc" --version
    assert_success
    assert_output_contains "Raccoon version"
}

@test "rcc: -V prints version" {
    run bash "$SCRIPT_DIR/rcc" -V
    assert_success
    assert_output_contains "Raccoon version"
}

@test "rcc: --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" --help
    assert_success
}

@test "rcc: -h exits 0" {
    run bash "$SCRIPT_DIR/rcc" -h
    assert_success
}

@test "rcc: help exits 0" {
    run bash "$SCRIPT_DIR/rcc" help
    assert_success
}

@test "rcc: unknown command exits 1" {
    run bash "$SCRIPT_DIR/rcc" nonexistent123xyz
    assert_failure
}

@test "rcc: ssh --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" ssh --help
    assert_success
}

@test "rcc: git --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" git --help
    assert_success
}

@test "rcc: upgrade --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" upgrade --help
    assert_success
}

@test "rcc: ports --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" ports --help
    assert_success
}

@test "rcc: battery --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" battery --help
    assert_success
}

@test "rcc: backup --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" backup --help
    assert_success
}

@test "rcc: env --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" env --help
    assert_success
}

@test "rcc: network --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" network --help
    assert_success
}

@test "rcc: disk --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" disk --help
    assert_success
}

@test "rcc: memory --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" memory --help
    assert_success
}

@test "rcc: startup --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" startup --help
    assert_success
}

@test "rcc: trash --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" trash --help
    assert_success
}

@test "rcc: fonts --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" fonts --help
    assert_success
}

@test "rcc: history --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" history --help
    assert_success
}

@test "rcc: certs --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" certs --help
    assert_success
}

@test "rcc: docker --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" docker --help
    assert_success
}

@test "rcc: xcode --help exits 0" {
    run bash "$SCRIPT_DIR/rcc" xcode --help
    assert_success
}

@test "rcc: audit fix no crash" {
    run bash "$SCRIPT_DIR/rcc" audit fix 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "rcc: audit deep no crash" {
    run bash "$SCRIPT_DIR/rcc" audit deep 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "rcc: audit quiet no crash" {
    run bash "$SCRIPT_DIR/rcc" audit quiet 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "rcc: audit json no crash" {
    run bash "$SCRIPT_DIR/rcc" audit json 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "rcc: audit history no crash" {
    run bash "$SCRIPT_DIR/rcc" audit history 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "rcc: audit watch no crash" {
    run bash "$SCRIPT_DIR/rcc" audit watch 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "rcc: completion bash prints functions" {
    run bash "$SCRIPT_DIR/rcc" completion bash
    assert_success
    assert_output_contains "complete -F"
}

@test "rcc: completion zsh prints functions" {
    run bash "$SCRIPT_DIR/rcc" completion zsh
    assert_success
}

@test "rcc: completion bad arg fails" {
    run bash "$SCRIPT_DIR/rcc" completion fish
    assert_failure
}

