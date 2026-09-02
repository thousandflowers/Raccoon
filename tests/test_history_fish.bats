load test_helper
setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

# rcc looked for fish history in ~/.local/share/fish/history/default, which is
# not where any version of fish keeps it — so a fish user's count was always 0,
# reported as confidently as a real number. And fish writes two lines per
# command, so finding the file without knowing its shape doubles the count.

_write_fish_history() {
    mkdir -p "$HOME/.local/share/fish"
    cat > "$HOME/.local/share/fish/fish_history" <<'HIST'
- cmd: echo one
  when: 1788315507
- cmd: git status
  when: 1788315508
- cmd: brew upgrade
  when: 1788315509
HIST
}

@test "history: finds fish where fish actually keeps it" {
    _write_fish_history
    run bash "$SCRIPT_DIR/bin/history.sh" --json
    assert_success
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["counts"]["fish"] == 3, f"expected 3 commands, got {d[chr(39)+chr(39)] if False else d}"
'
}

@test "history: a fish entry is one command, not the two lines it takes" {
    _write_fish_history
    run bash "$SCRIPT_DIR/bin/history.sh" --json
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["counts"]["fish"] != 6, "counted lines, not commands"
'
}

@test "history: no fish history is zero, and the document still opens" {
    run bash "$SCRIPT_DIR/bin/history.sh" --json
    assert_success
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["counts"]["fish"] == 0, d
'
}

@test "history: the text report agrees with the JSON about fish" {
    _write_fish_history
    run bash "$SCRIPT_DIR/bin/history.sh"
    assert_success
    assert_output_contains "3"
}
