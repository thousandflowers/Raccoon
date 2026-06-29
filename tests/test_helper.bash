# shellcheck disable=SC2155,SC2034,SC2154

# Common test helpers for bats tests.
# `status` and `output` are set by bats after `run`.
# Source this BEFORE loading any Raccoon lib files.

_common_setup() {
	setup_raccoon_env
}

setup_raccoon_env() {
	export RACCOON_TEST=1
	export SCRIPT_DIR="${BATS_TEST_DIRNAME}/.."
	export HOME="${BATS_TMPDIR}/raccoon-home-$$"
	mkdir -p "$HOME"/{.raccoon,.local/bin}
}

teardown_raccoon_env() {
	# ponytail: chmod before rm handles read-only files from go install etc
	chmod -R +w "${HOME}" 2>/dev/null || true
	rm -rf "${HOME}" 2>/dev/null || true
}

# Run a command with assert status
assert_success() {
	[[ "$status" -eq 0 ]]
}

assert_failure() {
	[[ "$status" -ne 0 ]]
}

# A finished audit/fleet run exits with a SEMANTIC code (0 pass, 1 fail,
# 2 warn) — see issue #39. So a run that completes is any of 0/1/2; anything
# higher (127 not-found, 130 interrupt, …) is a real failure. Use this instead
# of assert_success for `rcc audit` / `rcc fleet audit` process runs, then keep
# asserting on the actual artifact (file written, output content).
assert_audit_exit() {
	if [[ "$status" -lt 0 || "$status" -gt 2 ]]; then
		echo "unexpected audit exit status: $status" >&2
		echo "$output" >&2
		return 1
	fi
}

assert_output() {
	local expected="$1"
	[[ "$output" == "$expected" ]]
}

assert_output_contains() {
	local needle="$1"
	[[ "$output" == *"$needle"* ]]
}
