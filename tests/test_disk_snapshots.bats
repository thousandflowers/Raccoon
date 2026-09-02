load test_helper
setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

# 24 local snapshots existed on this Mac while rcc reported none: it had no
# code that looked for them at all. Mole found them; Raccoon did not.

@test "disk: reports local APFS snapshots" {
    run bash "$SCRIPT_DIR/bin/disk.sh"
    assert_success
    assert_output_contains "Snapshots"
}

@test "disk: counts the snapshots on the Data volume, not the sealed System one" {
    # `diskutil apfs listSnapshots /` answers for the sealed System volume and
    # finds one OS-update snapshot. The Time Machine snapshots that pin deleted
    # space live on the Data volume, and asking the wrong one reports 1 of 24.
    local data system
    data=$(diskutil apfs listSnapshots /System/Volumes/Data 2>/dev/null | grep -c 'Name:' || true)
    system=$(diskutil apfs listSnapshots / 2>/dev/null | grep -c 'Name:' || true)
    [[ "$data" -eq 0 ]] && skip "no local snapshots on this Mac"
    run bash "$SCRIPT_DIR/bin/disk.sh"
    assert_output_contains "$data"
    [[ "$data" -ne "$system" ]] || skip "both volumes agree here; nothing to tell apart"
}

@test "disk --json: snapshots are in the document" {
    run bash "$SCRIPT_DIR/bin/disk.sh" --json
    assert_success
    assert_output_contains '"snapshots"'
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "disk: does not ask for sudo to find snapshots" {
    # diskutil apfs listSnapshots answers unprivileged. A Touch ID prompt for a
    # read-only disk report would be a defect of its own. The helper has no
    # refute, so this asserts on the absence directly.
    run bash "$SCRIPT_DIR/bin/disk.sh"
    [[ "$output" != *"Password:"* ]] || { echo "asked for sudo: $output"; return 1; }
    [[ "$output" != *"sudo"* ]] || { echo "mentions sudo: $output"; return 1; }
}
