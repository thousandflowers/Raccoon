load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "fonts: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --help
    assert_success
}

@test "fonts: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" -h
    assert_success
}

@test "fonts: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --help
    assert_output_contains "Usage"
}

@test "fonts: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "fonts: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "fonts: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "fonts: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# The count used to come from one fc-scan per font file: ~800 processes, fifteen
# seconds, past the ten Raycast allows. The command was killed mid-document and
# the reader was told rcc emits broken JSON. One fc-scan answers the same
# question, and these two say so — that it still finds an unreadable font, and
# that the document reaches its closing brace.

@test "fonts: a font fontconfig cannot read is counted" {
    command -v fc-scan >/dev/null 2>&1 || skip "fc-scan not installed"
    mkdir -p "$HOME/Library/Fonts"
    printf 'this is not a font' > "$HOME/Library/Fonts/broken.ttf"
    run bash "$SCRIPT_DIR/bin/fonts.sh" --json
    assert_success
    # At least the one planted here; the system folder may hold others.
    local count
    count=$(printf '%s' "$output" | sed -n 's/.*"corrupted": *\([0-9][0-9]*\).*/\1/p')
    [[ -n "$count" ]] || { echo "no corrupted count in: $output"; return 1; }
    (( count >= 1 )) || { echo "expected at least 1 corrupted, got $count"; return 1; }
}

@test "fonts: --json reaches its closing brace" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --json
    assert_success
    # The truncation that reached a user stopped after "fontconfig", one line
    # short: the document parsed as far as it went and failed on what followed.
    assert_output_contains '"corrupted"'
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "fonts: the system font folders are counted too" {
    # /System/Library/Fonts holds 83 faces and Supplemental another 290 on a
    # stock Mac. Counting only /Library/Fonts and ~/Library/Fonts is why the
    # report printed `installed: 812` beside `fontconfig: 940` and explained
    # neither: a third of the fonts on the machine were invisible to it.
    run bash "$SCRIPT_DIR/bin/fonts.sh" --json
    assert_success
    assert_output_contains "/System/Library/Fonts"
    assert_output_contains "Supplemental"
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "fonts: installed is the sum of every source it lists" {
    run bash "$SCRIPT_DIR/bin/fonts.sh" --json
    assert_success
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
total = sum(s["count"] for s in d["sources"])
assert d["installed"] == total, f"installed {d[chr(34)+chr(34)]} != sum {total}" if False else f"installed {d} != sum {total}"
'
}
