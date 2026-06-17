load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "audit: flag --deep exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --deep 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --fix exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --fix 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --dry-run exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --dry-run 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --force exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --force 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --quiet exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --quiet 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --json exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --json 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --csv exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --csv 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --html exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --html 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --history exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --history 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --diff exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --diff 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --watch exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --watch 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --alert exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --alert 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: flag --notify exits 0 or 1" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --notify 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo deep+fix" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --deep --fix 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo deep+dry-run" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --deep --dry-run 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo deep+quiet" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --deep --quiet 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo deep+json" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --deep --json 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo deep+csv" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --deep --csv 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo fix+dry-run" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --fix --dry-run 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo fix+quiet" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --fix --quiet 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo fix+json" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --fix --json 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo fix+csv" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --fix --csv 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo dry-run+quiet" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --dry-run --quiet 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo dry-run+json" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --dry-run --json 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo dry-run+csv" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --dry-run --csv 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo quiet+json" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --quiet --json 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo quiet+csv" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --quiet --csv 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: combo json+csv" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --json --csv 2>&1 || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --help
    assert_success
}

@test "audit: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/audit.sh" -h
    assert_success
}

@test "audit: --nonexistent silently ignored" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "audit: multi-bad-flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/audit.sh" --bogus --also-bogus
    [[ $status -eq 0 || $status -eq 1 ]]
}

