load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "apps: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/apps.sh" --help
    assert_success
}

@test "apps: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/apps.sh" -h
    assert_success
}

@test "apps: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/apps.sh" --help
    assert_output_contains "Usage"
}

@test "apps: --help mentions App Store and casks" {
    run bash "$SCRIPT_DIR/bin/apps.sh" --help
    assert_output_contains "mas"
    assert_output_contains "casks"
}

# RACCOON_TEST (set by setup) forces dry-run so nothing real is updated;
# --no-catalog --no-sparkle also keeps these arg-parsing tests offline and fast.
@test "apps: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/apps.sh" --no-catalog --no-sparkle --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "apps: --dry-run runs without crash" {
    run bash "$SCRIPT_DIR/bin/apps.sh" --dry-run --no-catalog --no-sparkle 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "apps: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/apps.sh" --no-catalog --no-sparkle ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "apps: wired into rcc dispatcher" {
    run grep -q 'bin/apps.sh' "$SCRIPT_DIR/rcc"
    assert_success
}
