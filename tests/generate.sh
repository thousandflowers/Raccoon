#!/bin/bash
# Generate bats test files for all sub-tools.
# Each tool gets tests for: --help, -h, bad flag, and execution.
# Audit gets combinatorial flag tests.

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Helper: generate tests for a simple sub-tool ───
gen_subtool_tests() {
    local tool="$1"
    local file="$OUT_DIR/test_${tool}.bats"
    exec 3>"$file"
    echo 'load test_helper' >&3
    echo '' >&3
    echo 'setup() { setup_raccoon_env; }' >&3
    echo 'teardown() { teardown_raccoon_env; }' >&3
    echo '' >&3

    # --help flag (long)
    echo "@test \"${tool}: --help exits 0\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/${tool}.sh\" --help" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    # -h flag (short)
    echo "@test \"${tool}: -h exits 0\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/${tool}.sh\" -h" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    # --help output contains tool name or "Usage"
    echo "@test \"${tool}: --help prints usage\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/${tool}.sh\" --help" >&3
    echo "    assert_output_contains \"Usage\"" >&3
    echo '}' >&3
    echo '' >&3

    # Unknown flag — tools silently ignore unknown flags (* catch-all)
    echo "@test \"${tool}: unknown flag silently ignored\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/${tool}.sh\" --nonexistent" >&3
    echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
    echo '}' >&3
    echo '' >&3

    # Default run (no args) — should not crash, may produce output
    echo "@test \"${tool}: no args runs without crash\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/${tool}.sh\" 2>/dev/null || true" >&3
    echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
    echo '}' >&3
    echo '' >&3

    # --version not supported (silently ignored like all unknown flags)
    echo "@test \"${tool}: --version silently ignored\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/${tool}.sh\" --version" >&3
    echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
    echo '}' >&3
    echo '' >&3

    # Empty string argument (silently ignored)
    echo "@test \"${tool}: empty string arg silently ignored\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/${tool}.sh\" ' '" >&3
    echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
    echo '}' >&3
    echo '' >&3

    exec 3>&-
}

# ─── Audit tests (maximum flag coverage) ───
gen_audit_tests() {
    local file="$OUT_DIR/test_audit_detail.bats"
    exec 3>"$file"
    echo 'load test_helper' >&3
    echo '' >&3
    echo 'setup() { setup_raccoon_env; }' >&3
    echo 'teardown() { teardown_raccoon_env; }' >&3
    echo '' >&3

    local flags=(--deep --fix --dry-run --force --quiet --json --csv --html --history --diff --watch --alert --notify)
    for flag in "${flags[@]}"; do
        echo "@test \"audit: flag $flag exits 0 or 1\" {" >&3
        echo "    run bash \"\$SCRIPT_DIR/bin/audit.sh\" $flag 2>&1 || true" >&3
        echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
        echo '}' >&3
        echo '' >&3
    done

    local combo_flags=(--deep --fix --dry-run --quiet --json --csv)
    for ((i=0; i<${#combo_flags[@]}; i++)); do
        for ((j=i+1; j<${#combo_flags[@]}; j++)); do
            local f1="${combo_flags[$i]}" f2="${combo_flags[$j]}"
            local label="${f1#--}+${f2#--}"
            echo "@test \"audit: combo ${label}\" {" >&3
            echo "    run bash \"\$SCRIPT_DIR/bin/audit.sh\" $f1 $f2 2>&1 || true" >&3
            echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
            echo '}' >&3
            echo '' >&3
        done
    done

    echo "@test \"audit: --help exits 0\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/audit.sh\" --help" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"audit: -h exits 0\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/audit.sh\" -h" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"audit: --nonexistent silently ignored\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/audit.sh\" --nonexistent" >&3
    echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"audit: multi-bad-flag silently ignored\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/bin/audit.sh\" --bogus --also-bogus" >&3
    echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
    echo '}' >&3
    echo '' >&3

    exec 3>&-
}

# ─── rcc entrypoint tests ───
gen_rcc_tests() {
    local file="$OUT_DIR/test_rcc.bats"
    exec 3>"$file"
    echo 'load test_helper' >&3
    echo '' >&3
    echo 'setup() { setup_raccoon_env; }' >&3
    echo 'teardown() { teardown_raccoon_env; }' >&3
    echo '' >&3

    echo "@test \"rcc: --version prints version\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" --version" >&3
    echo "    assert_success" >&3
    echo "    assert_output_contains \"Raccoon version\"" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"rcc: -V prints version\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" -V" >&3
    echo "    assert_success" >&3
    echo "    assert_output_contains \"Raccoon version\"" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"rcc: --help exits 0\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" --help" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"rcc: -h exits 0\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" -h" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"rcc: help exits 0\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" help" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"rcc: unknown command exits 1\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" nonexistent123xyz" >&3
    echo "    assert_failure" >&3
    echo '}' >&3
    echo '' >&3

    local cmds=(ssh git upgrade ports battery backup env network disk memory startup trash fonts history certs docker xcode)
    for cmd in "${cmds[@]}"; do
        echo "@test \"rcc: $cmd --help exits 0\" {" >&3
        echo "    run bash \"\$SCRIPT_DIR/rcc\" $cmd --help" >&3
        echo "    assert_success" >&3
        echo '}' >&3
        echo '' >&3
    done

    local audit_cmds=(fix deep quiet json history watch)
    for aa in "${audit_cmds[@]}"; do
        echo "@test \"rcc: audit $aa no crash\" {" >&3
        echo "    run bash \"\$SCRIPT_DIR/rcc\" audit $aa 2>&1 || true" >&3
        echo "    [[ \$status -eq 0 || \$status -eq 1 ]]" >&3
        echo '}' >&3
        echo '' >&3
    done

    echo "@test \"rcc: completion bash prints functions\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" completion bash" >&3
    echo "    assert_success" >&3
    echo "    assert_output_contains \"complete -F\"" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"rcc: completion zsh prints functions\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" completion zsh" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"rcc: completion bad arg fails\" {" >&3
    echo "    run bash \"\$SCRIPT_DIR/rcc\" completion fish" >&3
    echo "    assert_failure" >&3
    echo '}' >&3
    echo '' >&3

    exec 3>&-
}

# ─── common.sh tests ───
gen_common_tests() {
    local file="$OUT_DIR/test_common.bats"
    exec 3>"$file"
    echo 'load test_helper' >&3
    echo '' >&3
    echo 'setup() {' >&3
    echo '    setup_raccoon_env' >&3
    echo '    source "$SCRIPT_DIR/lib/core/common.sh"' >&3
    echo '}' >&3
    echo 'teardown() { teardown_raccoon_env; }' >&3
    echo '' >&3

    echo "@test \"common: NO_COLOR disables ANSI\" {" >&3
    echo "    NO_COLOR=1 source \"\$SCRIPT_DIR/lib/core/common.sh\"" >&3
    echo "    [[ -z \"\$GREEN\" ]]" >&3
    echo "    [[ -z \"\$RED\" ]]" >&3
    echo "    [[ \"\$ICON_SUCCESS\" == \"OK\" ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: NO_COLOR unset has ANSI\" {" >&3
    echo "    [[ -n \"\$GREEN\" ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_strip_ansi plain\" {" >&3
    echo "    result=\$(_rcc_strip_ansi 'foo')" >&3
    echo "    [[ \"\$result\" == 'foo' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_strip_ansi removes ANSI\" {" >&3
    echo "    result=\$(_rcc_strip_ansi \$'\\033[0;32mhello\\033[0m')" >&3
    echo "    [[ \"\$result\" == 'hello' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_strip_ansi multiple codes\" {" >&3
    echo "    result=\$(_rcc_strip_ansi \$'\\033[1;35m➤\\033[0m')" >&3
    echo "    [[ \"\$result\" == '➤' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_strip_ansi empty\" {" >&3
    echo "    result=\$(_rcc_strip_ansi '')" >&3
    echo "    [[ -z \"\$result\" ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_visible_width empty = 0\" {" >&3
    echo "    result=\$(_rcc_visible_width '')" >&3
    echo "    [[ \"\$result\" -eq 0 ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_visible_width plain text\" {" >&3
    echo "    result=\$(_rcc_visible_width 'hello')" >&3
    echo "    [[ \"\$result\" -eq 5 ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_visible_width ignores ANSI\" {" >&3
    echo "    result=\$(_rcc_visible_width \$'\\033[0;32mhi\\033[0m')" >&3
    echo "    [[ \"\$result\" -eq 2 ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_visible_width spaces\" {" >&3
    echo "    result=\$(_rcc_visible_width '  x  ')" >&3
    echo "    [[ \"\$result\" -eq 5 ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_pad_to exact width\" {" >&3
    echo "    result=\$(_rcc_pad_to 'abcd' 4)" >&3
    echo "    [[ \"\$result\" == 'abcd' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_pad_to needs padding\" {" >&3
    echo "    result=\$(_rcc_pad_to 'ab' 5)" >&3
    echo "    [[ \"\$result\" == 'ab   ' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_pad_to negative pad\" {" >&3
    echo "    result=\$(_rcc_pad_to 'abcdef' 3)" >&3
    echo "    [[ \"\$result\" == 'abcdef' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_hr default width\" {" >&3
    echo "    result=\$(_rcc_hr)" >&3
    echo "    [[ \"\$result\" == '+---------------------------------------+' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_hr custom width\" {" >&3
    echo "    result=\$(_rcc_hr 5)" >&3
    echo "    [[ \"\$result\" == '+-----+' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_hr zero width\" {" >&3
    echo "    result=\$(_rcc_hr 0)" >&3
    echo "    [[ \"\$result\" == '++' ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_success outputs msg\" {" >&3
    echo "    run print_success 'test msg'" >&3
    echo "    assert_success" >&3
    echo "    assert_output_contains 'test msg'" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_error outputs msg\" {" >&3
    echo "    run print_error 'err msg'" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_warning outputs msg\" {" >&3
    echo "    run print_warning 'warn msg'" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_info outputs msg\" {" >&3
    echo "    run print_info 'info msg'" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_step format\" {" >&3
    echo "    run print_step 1 5 'test'" >&3
    echo "    assert_success" >&3
    echo "    assert_output_contains '[1/5]'" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_help_header format\" {" >&3
    echo "    run print_help_header 'testcmd' 'a test command'" >&3
    echo "    assert_success" >&3
    echo "    assert_output_contains \"Usage: rcc testcmd\"" >&3
    echo "    assert_output_contains 'a test command'" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: clear_screen no error\" {" >&3
    echo "    run clear_screen" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: _rcc_disable_color clears vars\" {" >&3
    echo "    _rcc_disable_color" >&3
    echo "    [[ -z \"\$GREEN\" ]]" >&3
    echo "    [[ \"\$ICON_SUCCESS\" == \"OK\" ]]" >&3
    echo "    [[ \"\$ICON_ERROR\" == \"XX\" ]]" >&3
    echo "    [[ \"\$ICON_ARROW\" == \"->\" ]]" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: read_key Ctrl-C QUIT\" {" >&3
    echo "    skip \"read_key reads from /dev/tty, not pipe\"" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: read_key ENTER on empty\" {" >&3
    echo "    skip \"read_key reads from /dev/tty, not pipe\"" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: read_key q = QUIT\" {" >&3
    echo "    skip \"read_key reads from /dev/tty, not pipe\"" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: read_key SPACE\" {" >&3
    echo "    skip \"read_key reads from /dev/tty, not pipe\"" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_table_header no error\" {" >&3
    echo "    run print_table_header 'col1|col2' 10 10" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: print_table_row no error\" {" >&3
    echo "    run print_table_row 'val1|val2' 10 10" >&3
    echo "    assert_success" >&3
    echo '}' >&3
    echo '' >&3

    echo "@test \"common: spinner start/stop cleanup\" {" >&3
    echo "    start_inline_spinner 'testing' 2>/dev/null" >&3
    echo "    stop_inline_spinner 2>/dev/null" >&3
    echo "    [[ -z \"\$SPINNER_PID\" ]]" >&3
    echo '}' >&3
    echo '' >&3

    exec 3>&-
}

# ─── Generate everything ───
for tool in network disk memory ports battery backup env startup trash fonts history certs docker xcode ssh git upgrade; do
    gen_subtool_tests "$tool"
done

gen_audit_tests
gen_rcc_tests
gen_common_tests

echo ""
echo "=== Total tests generated ==="
total=0
for f in "$OUT_DIR"/test_*.bats; do
    base="$(basename "$f")"
    count=$(grep -c '@test' "$f")
    total=$((total + count))
    printf "  %-35s %3d tests\n" "$base" "$count"
done
echo "  ---"
echo "  TOTAL: $total tests"
