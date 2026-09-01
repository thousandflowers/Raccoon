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

NOT_IMPLEMENTED="xcode"
IMPLEMENTED="battery certs disk docker env fonts history network overlap ports startup trash wifi"

@test "json: the ones that never implemented --json exit 64" {
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

# Three scripts have now died on a directory or a command that was simply not
# there: battery on a Mac with no battery, git with no repositories, fonts with
# no ~/Library/Fonts. find and grep exit non-zero on nothing, pipefail
# propagates it, and set -e turns "nothing to report" into "no output at all".
@test "json: an empty HOME is a report, not a crash" {
	command -v python3 > /dev/null || skip "python3 not available"
	local c empty bad=""
	empty="$(mktemp -d)"
	for c in $IMPLEMENTED; do
		run env HOME="$empty" RCC_NO_PROMPT=1 bash "$SCRIPT_DIR/bin/$c.sh" --json
		if [[ "$status" -ne 0 ]] ||
			! printf '%s' "$output" | python3 -m json.tool > /dev/null 2>&1; then
			bad+="$c "
		fi
	done
	rmdir "$empty" 2> /dev/null || true
	[[ -z "$bad" ]] || {
		echo "no JSON with an empty HOME: $bad" >&2
		false
	}
}

@test "json: the ones that do implement it still say so in their help" {
	local c
	for c in $IMPLEMENTED; do
		run bash "$SCRIPT_DIR/bin/$c.sh" --help
		assert_success
		assert_output_contains "--json"
	done
}

# disk.sh parses its flags with `while [[ $# -gt 0 ]]` and a shift inside each
# branch. A --json branch without one spins forever: the command hung for ten
# minutes before anyone noticed it was not slow, it was stuck.
@test "json: --json terminates, and quickly" {
	command -v python3 > /dev/null || skip "python3 not available"
	local c
	for c in $IMPLEMENTED; do
		# Run it in the background and give it a hard deadline: a spinning
		# argument loop produces no output, so a timeout is the only signal.
		bash "$SCRIPT_DIR/bin/$c.sh" --json > /dev/null 2>&1 &
		local pid=$!
		local waited=0
		while kill -0 "$pid" 2> /dev/null && [[ $waited -lt 60 ]]; do
			sleep 1
			waited=$((waited + 1))
		done
		if kill -0 "$pid" 2> /dev/null; then
			kill -9 "$pid" 2> /dev/null || true
			echo "$c --json did not finish in 60s" >&2
			false
		fi
		wait "$pid" 2> /dev/null || true
	done
}
