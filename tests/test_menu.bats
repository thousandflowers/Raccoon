load test_helper

setup() {
	setup_raccoon_env
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/lib/core/commands.sh"
}
teardown() { teardown_raccoon_env; }

# The bash menu and the Go menu are two lists of the same thing in two
# languages, and comparing them to each other is what let both of them go on
# missing wifi. Each is checked against the scripts that actually exist instead.

_bin_commands() {
	local p
	for p in "$SCRIPT_DIR"/bin/*.sh; do
		p="${p##*/}"
		printf '%s\n' "${p%.sh}"
	done | sort
}

_menu_commands() {
	local item
	for item in "${MENU_ITEMS[@]}"; do
		[[ "$item" == "== "* || "$item" == "---" ]] && continue
		printf '%s\n' "${item%%:*}"
	done | sort
}

@test "menu: every bin/*.sh has a row" {
	local missing
	missing="$(comm -23 <(_bin_commands) <(_menu_commands))"
	[[ -z "$missing" ]] || { echo "scripts with no menu row: $missing" >&2; false; }
}

@test "menu: every row has a bin/*.sh" {
	local phantom
	phantom="$(comm -13 <(_bin_commands) <(_menu_commands))"
	[[ -z "$phantom" ]] || { echo "menu rows with no script: $phantom" >&2; false; }
}

@test "menu: the two counts agree" {
	[[ "$(_bin_commands | wc -l)" -eq "$(_menu_commands | wc -l)" ]]
}

@test "menu: the four categories are there, and carry nothing to run" {
	local item found=0
	for item in "${MENU_ITEMS[@]}"; do
		[[ "$item" == "== "* ]] || continue
		found=$((found + 1))
		[[ "$item" != *:* ]]   # a heading has no description to run away with
	done
	[[ "$found" -eq 4 ]]
}

@test "menu: a heading is not dispatchable" {
	local item n=1
	for item in "${MENU_ITEMS[@]}"; do
		if [[ "$item" == "== "* ]]; then
			run run_cmd "$n"
			assert_success
			[[ -z "$output" ]]
		fi
		n=$((n + 1))
	done
}

@test "menu: searching never returns a heading" {
	run _filter_menu_items "e"
	assert_success
	[[ "$output" != *"== "* ]]
}

# --- rcc --help -------------------------------------------------------------

@test "help: the six ways of launching audit are still listed" {
	run bash "$SCRIPT_DIR/rcc" --help
	assert_success
	local v
	for v in deep quiet fix json history watch; do
		assert_output_contains "rcc audit $v"
	done
}

@test "help: the category headings never reach it" {
	run bash "$SCRIPT_DIR/rcc" --help
	assert_success
	[[ "$output" != *"=="* ]]
	[[ "$output" != *"── "* ]]
}

@test "help: two columns, one command per line, nothing else indented" {
	run bash "$SCRIPT_DIR/rcc" --help
	assert_success
	[[ "$(printf '%s\n' "$output" | grep -c '^  rcc ')" -eq 28 ]]
}

# --- fleet's default --------------------------------------------------------

@test "fleet: no subcommand prints the subcommands instead of auditing" {
	run bash "$SCRIPT_DIR/bin/fleet.sh"
	assert_success
	assert_output_contains "Usage: rcc fleet <command>"
	assert_output_contains "audit            Audit every host"
	# The audit banner must not appear: a bare invocation opens no connections.
	[[ "$output" != *"Fleet Audit"* ]]
}

@test "fleet: --help still works the way it did" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" --help
	assert_success
	assert_output_contains "Usage: rcc fleet <command>"
}
