load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

# Eight commands declared --json in their argument parser and advertised it in
# their --help, and the case body was empty: the flag was accepted and the human
# report printed instead. Nothing complained for six releases, because silence
# does not complain. These tests are what makes it complain.
#
# The refusal is not "unknown option": the flag is planned, and someone who tries
# again in two months has to be able to tell the difference.

NOT_IMPLEMENTED="certs disk docker fonts history network startup xcode"
IMPLEMENTED="battery overlap ports trash wifi"

@test "json: the eight that never implemented --json exit 64" {
	local c
	for c in $NOT_IMPLEMENTED; do
		run bash "$SCRIPT_DIR/bin/$c.sh" --json
		# 64 is EX_USAGE. Deliberately not 2, which audit and fleet already use
		# for "warnings only" and which the Raycast extension reads that way.
		[[ "$status" -eq 64 ]] || { echo "$c exited $status, want 64" >&2; false; }
	done
}

@test "json: the refusal says not implemented, not unknown" {
	local c
	for c in $NOT_IMPLEMENTED; do
		run bash "$SCRIPT_DIR/bin/$c.sh" --json
		assert_output_contains "--json is not implemented yet"
		[[ "$output" != *"Unknown option"* ]]
	done
}

@test "json: the refusal prints nothing to stdout" {
	local c out
	for c in $NOT_IMPLEMENTED; do
		out="$(bash "$SCRIPT_DIR/bin/$c.sh" --json 2>/dev/null || true)"
		[[ -z "$out" ]] || { echo "$c printed to stdout: $out" >&2; false; }
	done
}

@test "json: none of the eight advertises --json in its help any more" {
	local c
	for c in $NOT_IMPLEMENTED; do
		run bash "$SCRIPT_DIR/bin/$c.sh" --help
		assert_success
		[[ "$output" != *"--json"* ]] || { echo "$c --help still offers --json" >&2; false; }
	done
}

@test "json: the ones that do implement it still exit 0 and print JSON" {
	command -v python3 > /dev/null || skip "python3 not available"
	local c out
	for c in $IMPLEMENTED; do
		# The || is what makes this loop able to name the command that broke.
		# Written as a bare assignment, set -e aborts on the failing command
		# substitution and the check on the next line never runs, so the failure
		# reads as "line 57" and the log never says which of the five it was.
		out="$(RCC_NO_PROMPT=1 bash "$SCRIPT_DIR/bin/$c.sh" --json 2>/dev/null)" ||
			{ echo "$c exited non-zero" >&2; false; }
		printf '%s' "$out" | python3 -m json.tool > /dev/null ||
			{ echo "$c did not print valid JSON" >&2; false; }
	done
}

@test "json: the ones that do implement it still say so in their help" {
	local c
	for c in $IMPLEMENTED; do
		run bash "$SCRIPT_DIR/bin/$c.sh" --help
		assert_success
		assert_output_contains "--json"
	done
}
