load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "history: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/history.sh" --help
    assert_success
}

@test "history: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/history.sh" -h
    assert_success
}

@test "history: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/history.sh" --help
    assert_output_contains "Usage"
}

@test "history: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/history.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "history: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/history.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "history: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/history.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "history: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/history.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "history --json: recent is newest first, distinct, and only command names" {
    mkdir -p "$BATS_TEST_TMPDIR/h"
    cat > "$BATS_TEST_TMPDIR/h/.zsh_history" <<'EOF'
: 1700000000:0;oldest --flag
: 1700000001:0;ls -la
: 1700000002:0;API_TOKEN=s3cret curl https://example.com
: 1700000003:0;/Users/someone/private/deploy --prod
: 1700000004:0;clear; cd /Users/someone
: 1700000005:0;clear; cd /Users/someone/else
EOF
    HOME="$BATS_TEST_TMPDIR/h" run bash "$SCRIPT_DIR/bin/history.sh" --json
    assert_success
    recent=$(printf '%s' "$output" | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)["recent"]))')
    [ "$recent" = "clear deploy curl ls oldest" ]
    [[ "$output" != *s3cret* ]]
    [[ "$output" != *private* ]]
}
