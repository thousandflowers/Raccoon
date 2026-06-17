load test_helper

setup() {
    setup_raccoon_env
    source "$SCRIPT_DIR/lib/core/common.sh"
}
teardown() { teardown_raccoon_env; }

@test "common: NO_COLOR disables ANSI" {
    NO_COLOR=1 source "$SCRIPT_DIR/lib/core/common.sh"
    [[ -z "$GREEN" ]]
    [[ -z "$RED" ]]
    [[ "$ICON_SUCCESS" == "OK" ]]
}

@test "common: NO_COLOR unset has ANSI" {
    [[ -n "$GREEN" ]]
}

@test "common: _rcc_strip_ansi plain" {
    result=$(_rcc_strip_ansi 'foo')
    [[ "$result" == 'foo' ]]
}

@test "common: _rcc_strip_ansi removes ANSI" {
    result=$(_rcc_strip_ansi $'\033[0;32mhello\033[0m')
    [[ "$result" == 'hello' ]]
}

@test "common: _rcc_strip_ansi multiple codes" {
    result=$(_rcc_strip_ansi $'\033[1;35m➤\033[0m')
    [[ "$result" == '➤' ]]
}

@test "common: _rcc_strip_ansi empty" {
    result=$(_rcc_strip_ansi '')
    [[ -z "$result" ]]
}

@test "common: _rcc_visible_width empty = 0" {
    result=$(_rcc_visible_width '')
    [[ "$result" -eq 0 ]]
}

@test "common: _rcc_visible_width plain text" {
    result=$(_rcc_visible_width 'hello')
    [[ "$result" -eq 5 ]]
}

@test "common: _rcc_visible_width ignores ANSI" {
    result=$(_rcc_visible_width $'\033[0;32mhi\033[0m')
    [[ "$result" -eq 2 ]]
}

@test "common: _rcc_visible_width spaces" {
    result=$(_rcc_visible_width '  x  ')
    [[ "$result" -eq 5 ]]
}

@test "common: _rcc_pad_to exact width" {
    result=$(_rcc_pad_to 'abcd' 4)
    [[ "$result" == 'abcd' ]]
}

@test "common: _rcc_pad_to needs padding" {
    result=$(_rcc_pad_to 'ab' 5)
    [[ "$result" == 'ab   ' ]]
}

@test "common: _rcc_pad_to negative pad" {
    result=$(_rcc_pad_to 'abcdef' 3)
    [[ "$result" == 'abcdef' ]]
}

@test "common: _rcc_hr default width" {
    result=$(_rcc_hr)
    [[ "$result" == '+---------------------------------------+' ]]
}

@test "common: _rcc_hr custom width" {
    result=$(_rcc_hr 5)
    [[ "$result" == '+-----+' ]]
}

@test "common: _rcc_hr zero width" {
    result=$(_rcc_hr 0)
    [[ "$result" == '++' ]]
}

@test "common: print_success outputs msg" {
    run print_success 'test msg'
    assert_success
    assert_output_contains 'test msg'
}

@test "common: print_error outputs msg" {
    run print_error 'err msg'
    assert_success
}

@test "common: print_warning outputs msg" {
    run print_warning 'warn msg'
    assert_success
}

@test "common: print_info outputs msg" {
    run print_info 'info msg'
    assert_success
}

@test "common: print_step format" {
    run print_step 1 5 'test'
    assert_success
    assert_output_contains '[1/5]'
}

@test "common: print_help_header format" {
    run print_help_header 'testcmd' 'a test command'
    assert_success
    assert_output_contains "Usage: rcc testcmd"
    assert_output_contains 'a test command'
}

@test "common: clear_screen no error" {
    run clear_screen
    assert_success
}

@test "common: _rcc_disable_color clears vars" {
    _rcc_disable_color
    [[ -z "$GREEN" ]]
    [[ "$ICON_SUCCESS" == "OK" ]]
    [[ "$ICON_ERROR" == "XX" ]]
    [[ "$ICON_ARROW" == "->" ]]
}

@test "common: read_key Ctrl-C QUIT" {
    skip "read_key reads from /dev/tty, not pipe"
}

@test "common: read_key ENTER on empty" {
    skip "read_key reads from /dev/tty, not pipe"
}

@test "common: read_key q = QUIT" {
    skip "read_key reads from /dev/tty, not pipe"
}

@test "common: read_key SPACE" {
    skip "read_key reads from /dev/tty, not pipe"
}

@test "common: print_table_header no error" {
    run print_table_header 'col1|col2' 10 10
    assert_success
}

@test "common: print_table_row no error" {
    run print_table_row 'val1|val2' 10 10
    assert_success
}

@test "common: spinner start/stop cleanup" {
    start_inline_spinner 'testing' 2>/dev/null
    stop_inline_spinner 2>/dev/null
    [[ -z "$SPINNER_PID" ]]
}

