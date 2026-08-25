load test_helper

# ensure_sudo decides whether rcc may raise a password prompt. Issue #23: the Go
# TUI holds the terminal in raw mode and runs its own key reader, so a prompt
# raised underneath it loses characters and sudo answers "Sorry, try again".
# The TUI sets RCC_NO_PROMPT=1 and authenticates before spawning the script.

setup() {
	setup_raccoon_env
	source "$SCRIPT_DIR/lib/core/common.sh"
	STUB_BIN="${BATS_TMPDIR}/sudo-stub-$$"
	mkdir -p "$STUB_BIN"
	export SUDO_LOG="${STUB_BIN}/argv.log"
	: >"$SUDO_LOG"
	cat >"${STUB_BIN}/sudo" <<'STUB'
#!/bin/bash
echo "$*" >>"$SUDO_LOG"
case "$1" in
	-n) exit "${STUB_SUDO_N:-1}" ;;
	-v) exit "${STUB_SUDO_V:-1}" ;;
esac
exit 0
STUB
	chmod +x "${STUB_BIN}/sudo"
	PATH="${STUB_BIN}:$PATH"
	# The guard under test sits after the test short-circuit at the top of
	# ensure_sudo, so it is unreachable while RACCOON_TEST is set.
	unset RACCOON_TEST
}

teardown() {
	rm -f "${STUB_BIN}/sudo" "$SUDO_LOG"
	rmdir "$STUB_BIN" 2>/dev/null || true
	teardown_raccoon_env
}

@test "sudo: ensure_sudo succeeds on a cached timestamp without prompting" {
	STUB_SUDO_N=0 run ensure_sudo
	assert_success
	grep -q -- '-n true' "$SUDO_LOG"
	! grep -q -- '-v' "$SUDO_LOG"
}

@test "sudo: ensure_sudo never prompts under RCC_NO_PROMPT" {
	STUB_SUDO_N=1 RCC_NO_PROMPT=1 run ensure_sudo
	assert_failure
	! grep -q -- '-v' "$SUDO_LOG"
	[[ "$output" != *"rcc needs sudo"* ]]
}

@test "sudo: ensure_sudo still prompts when it owns the terminal" {
	has_tty() { return 0; }   # a controlling terminal is reachable
	STUB_SUDO_N=1 STUB_SUDO_V=0 run ensure_sudo
	assert_success
	grep -q -- '-v' "$SUDO_LOG"
}

@test "sudo: ensure_sudo gives up when authentication fails" {
	has_tty() { return 0; }
	STUB_SUDO_N=1 STUB_SUDO_V=1 run ensure_sudo
	assert_failure
}

@test "sudo: keepalive is a no-op when sudo is not cached" {
	STUB_SUDO_N=1 run start_sudo_keepalive
	assert_success
	[[ -z "$_RCC_SUDO_KEEPALIVE_PID" ]]
}

# The keepalive loop sleeps as a background job it waits on. Killing only the
# subshell used to leave that sleep reparented to launchd for up to 50 seconds.
@test "sudo: keepalive leaves no orphaned sleep behind" {
	export STUB_SUDO_N=0
	start_sudo_keepalive
	[[ -n "$_RCC_SUDO_KEEPALIVE_PID" ]]

	local sleeper="" i=0
	while [[ -z "$sleeper" && $i -lt 40 ]]; do
		sleeper="$(pgrep -P "$_RCC_SUDO_KEEPALIVE_PID" | head -1)"
		i=$((i + 1))
		[[ -z "$sleeper" ]] && sleep 0.1
	done
	[[ -n "$sleeper" ]]

	stop_sudo_keepalive
	i=0
	while kill -0 "$sleeper" 2>/dev/null && [[ $i -lt 40 ]]; do
		i=$((i + 1)); sleep 0.1
	done
	! kill -0 "$sleeper" 2>/dev/null
}
