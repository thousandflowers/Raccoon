#!/usr/bin/env bats
# --json has one job: print a document a program can open. These tests run every
# command that implements it in environments a spawned process actually gets -
# no HOME, a trimmed PATH, nothing inherited - and check the output parses.
#
# Written because `rcc fonts --json` reached a user as "Expected double-quoted
# property name in JSON at position 254". Two causes, both invisible from an
# interactive shell: reading $HOME under `set -u` when the caller did not pass
# it, and interpolating a count from a pipeline that produced nothing.

setup() {
	REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	IMPLEMENTED="audit backup battery certs disk docker env fonts git history memory network overlap ports ssh startup trash wifi xcode"
	MIN_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

# Parses stdin as JSON, or fails naming the command and what came out.
assert_json() {
	local cmd="$1" out="$2"
	if [[ -z "$out" ]]; then
		echo "rcc $cmd --json printed nothing" >&2
		return 1
	fi
	if ! printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
		echo "rcc $cmd --json is not valid JSON:" >&2
		printf '%s\n' "$out" | head -20 >&2
		return 1
	fi
}

@test "json: valid with no HOME in the environment" {
	local c out
	for c in $IMPLEMENTED; do
		out="$(env -i PATH="$MIN_PATH" NO_COLOR=1 "$REPO/rcc" "$c" --json 2>/dev/null || true)"
		assert_json "$c" "$out"
	done
}

@test "json: valid with an empty HOME that exists but holds nothing" {
	local c out tmp
	tmp="$(mktemp -d)"
	for c in $IMPLEMENTED; do
		out="$(env -i PATH="$MIN_PATH" HOME="$tmp" NO_COLOR=1 "$REPO/rcc" "$c" --json 2>/dev/null || true)"
		assert_json "$c" "$out"
	done
	rm -rf "$tmp"
}

@test "json: valid with nothing on PATH but the system directories" {
	# fc-list, docker, mas and the rest live in Homebrew. A command that reports
	# on a tool it cannot find must say so in JSON, not stop mid-document.
	local c out
	for c in $IMPLEMENTED; do
		out="$(env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="$HOME" NO_COLOR=1 "$REPO/rcc" "$c" --json 2>/dev/null || true)"
		assert_json "$c" "$out"
	done
}
