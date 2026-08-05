load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "disk: physical disks table lists disks reported by diskutil" {
    local stub="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$stub"
    cat > "$stub/diskutil" <<'STUB'
#!/bin/bash
case "$1" in
    list) echo "/dev/disk99 (internal, physical):" ;;
    info) echo "   Disk Size:                 500.3 GB"; echo "   SMART Status:              Verified" ;;
esac
STUB
    chmod +x "$stub/diskutil"
    PATH="$stub:$PATH" run bash "$SCRIPT_DIR/bin/disk.sh"
    assert_output_contains "disk99"
}

@test "disk: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/disk.sh" --help
    assert_success
}

@test "disk: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/disk.sh" -h
    assert_success
}

@test "disk: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/disk.sh" --help
    assert_output_contains "Usage"
}

@test "disk: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/disk.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "disk: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/disk.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "disk: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/disk.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "disk: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/disk.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

