load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "xcode: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --help
    assert_success
}

@test "xcode: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" -h
    assert_success
}

@test "xcode: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --help
    assert_output_contains "Usage"
}

@test "xcode: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "xcode: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "xcode: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "xcode: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/xcode.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# --- measured, not read: the findings of 2026-09-02 ---------------------------

# A simctl with seventeen devices across four platforms, two booted, and two
# iPad Pro 11-inch models that differ only in their chip. Real format.
_stub_simctl() {
	STUB="${BATS_TEST_TMPDIR}/sim"
	mkdir -p "$STUB"
	cat > "$STUB/xcrun" <<'SH'
#!/bin/bash
cat <<'OUT'
== Devices ==
-- iOS 26.0 --
    iPhone 16e (11111111-1111-1111-1111-111111111111) (Shutdown)
    iPhone 16 (22222222-2222-2222-2222-222222222222) (Booted)
    iPhone 16 Plus (33333333-3333-3333-3333-333333333333) (Shutdown)
    iPhone 16 Pro (44444444-4444-4444-4444-444444444444) (Shutdown)
    iPhone 16 Pro Max (55555555-5555-5555-5555-555555555555) (Shutdown)
    iPhone 17 (66666666-6666-6666-6666-666666666666) (Shutdown)
    iPhone 17 Pro (77777777-7777-7777-7777-777777777777) (Shutdown)
    iPad Pro 11-inch (M4) (88888888-8888-8888-8888-888888888888) (Shutdown)
    iPad Pro 11-inch (M2) (99999999-9999-9999-9999-999999999999) (Booted)
    iPad Pro 13-inch (M4) (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA) (Shutdown)
    iPad mini (A17 Pro) (BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB) (Shutdown)
    iPad Air 11-inch (M3) (CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC) (Shutdown)
    iPod touch (7th generation) (DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD) (Shutdown)
-- xrOS 26.0 --
    Apple Vision Pro (EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE) (Shutdown)
-- watchOS 26.0 --
    Apple Watch Series 10 (46mm) (FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF) (Shutdown)
    Apple Watch Ultra 2 (49mm) (12121212-1212-1212-1212-121212121212) (Shutdown)
-- tvOS 26.0 --
    Apple TV 4K (3rd generation) (13131313-1313-1313-1313-131313131313) (Shutdown)
OUT
SH
	chmod +x "$STUB/xcrun"
}

@test "xcode: every simulator is listed, with its model, in both renderings" {
	command -v xcodebuild >/dev/null 2>&1 || skip "needs Xcode for the installed path"
	_stub_simctl
	PATH="$STUB:$PATH" run bash "$SCRIPT_DIR/bin/xcode.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
sims = json.load(sys.stdin)["simulators"]
names = [s["name"] for s in sims]
assert len(sims) == 17, len(sims)
assert sum(s["booted"] for s in sims) == 2
assert "Apple Vision Pro" in names and "iPod touch (7th generation)" in names, names
# Two devices, two names: the chip is what tells them apart.
assert "iPad Pro 11-inch (M4)" in names and "iPad Pro 11-inch (M2)" in names, names
'
	NO_COLOR=1 PATH="$STUB:$PATH" run bash "$SCRIPT_DIR/bin/xcode.sh"
	assert_success
	assert_output_contains "Total: 17 devices, 2 booted"
	assert_output_contains "Apple Vision Pro"
}

@test "xcode: DerivedData projects are the entries inside it, not the folder itself" {
	command -v xcodebuild >/dev/null 2>&1 || skip "needs Xcode for the installed path"
	mkdir -p "$HOME/Library/Developer/Xcode/DerivedData"
	run bash "$SCRIPT_DIR/bin/xcode.sh" --json
	assert_success
	[[ "$output" == *'"projects": 0'* ]]
	mkdir -p "$HOME/Library/Developer/Xcode/DerivedData"/{ProjA-abc,ProjB-def,ProjC-ghi}
	NO_COLOR=1 run bash "$SCRIPT_DIR/bin/xcode.sh"
	assert_success
	[[ "$output" == *"Projects"*"| 3 "* ]]
}

@test "xcode: the Command Line Tools alone are not Xcode" {
	[[ -d /Library/Developer/CommandLineTools ]] || skip "no Command Line Tools here"
	DEVELOPER_DIR=/Library/Developer/CommandLineTools run bash "$SCRIPT_DIR/bin/xcode.sh" --json
	assert_success
	[[ "$output" == *'"installed": false'* ]]
	[[ "$output" == *'"version": null'* ]]
	DEVELOPER_DIR=/Library/Developer/CommandLineTools NO_COLOR=1 run bash "$SCRIPT_DIR/bin/xcode.sh"
	assert_success
	assert_output_contains "Xcode is not installed"
}
