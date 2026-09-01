#!/usr/bin/env bats
# Tests for fleet mode. ssh is mocked via RACCOON_SSH so nothing touches the
# network. The mock emits synthetic JSON for audits and "ok" for status checks,
# and fails for any host containing "unreachable".

load test_helper

setup() {
	setup_raccoon_env
	mkdir -p "$HOME/.raccoon"
	cat > "$HOME/mockssh" <<'MOCK'
#!/bin/bash
cmd="${!#}"
host=""
for a in "$@"; do case "$a" in -*) ;; *@*) host="$a" ;; esac; done
case "$host" in *unreachable*) exit 1 ;; esac
case "$cmd" in
	*"echo ok"*) echo ok; exit 0 ;;
	*uname*) case "$host" in *linux*) echo Linux ;; *) echo Darwin ;; esac; exit 0 ;;
	*"bash -s"*) printf '{\n  "pass": 25,\n  "warning": 1,\n  "fail": 0,\n  "results": [\n    {"status": "warn", "category": "Net", "name": "Sharing", "value": "1"}\n  ]\n}\n'; exit 0 ;;
	*) printf 'RAN:%s\n' "$cmd"; exit 0 ;;
esac
exit 0
MOCK
	chmod +x "$HOME/mockssh"
	export RACCOON_SSH="$HOME/mockssh"
	export FLEET_TIMEOUT=5
}

teardown() {
	teardown_raccoon_env
}

@test "fleet list with no config reports none" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" list
	assert_audit_exit
	assert_output_contains "No hosts"
}

@test "fleet add then list shows the host" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" add mario@192.168.1.10
	assert_audit_exit
	run bash "$SCRIPT_DIR/bin/fleet.sh" list
	assert_audit_exit
	assert_output_contains "mario@192.168.1.10"
}

@test "fleet remove confirmed deletes the host" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" remove mario@192.168.1.10 <<< "y"
	assert_audit_exit
	run bash "$SCRIPT_DIR/bin/fleet.sh" list
	assert_output_contains "No hosts"
}

@test "fleet remove matches the whole line not a substring" {
	# Substring removal would also drop 192.168.1.10 (192.168.1.1 is a prefix).
	printf '%s\n' "host@192.168.1.1" "host@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" remove host@192.168.1.1
	assert_audit_exit
	run bash "$SCRIPT_DIR/bin/fleet.sh" list
	assert_audit_exit
	assert_output_contains "host@192.168.1.10"
}

@test "fleet status shows reachable hosts with a check mark" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" status
	assert_audit_exit
	assert_output_contains "✓"
}

@test "fleet status marks unreachable hosts with a cross" {
	printf '%s\n' "backup@unreachable.host" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" status
	assert_audit_exit
	assert_output_contains "✗"
}

@test "fleet audit aggregates reachable and unreachable hosts" {
	printf '%s\n' "mario@192.168.1.10" "admin@office.example.com" "backup@unreachable.host" \
		> "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit
	assert_audit_exit
	assert_output_contains "2/3 hosts reached"
}

@test "fleet audit --json starts with a brace" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit --json
	assert_audit_exit
	[[ "$output" == '{'* ]]
}

@test "fleet audit --report writes a Markdown report" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit --report "$HOME/fleet.md"
	assert_audit_exit
	[[ -f "$HOME/fleet.md" ]]
	grep -q "Fleet Audit" "$HOME/fleet.md"
}

@test "fleet audit --parallel 1 processes all hosts in order" {
	printf '%s\n' "a@192.168.1.1" "b@192.168.1.2" "c@192.168.1.3" \
		> "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit --parallel 1
	assert_audit_exit
	assert_output_contains "3/3 hosts reached"
}

@test "fleet audit with no config exits 0 with a message" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit
	assert_audit_exit
	assert_output_contains "No hosts configured"
}

# scan: RACCOON_SCAN_HOSTS injects candidates so discovery never touches the
# network and the nc port pre-check is skipped.

@test "fleet scan reports every candidate with its state" {
	export RACCOON_SCAN_HOSTS="192.168.1.10 nas-linux backup-unreachable"
	run bash "$SCRIPT_DIR/bin/fleet.sh" scan --user mario
	assert_audit_exit
	assert_output_contains "192.168.1.10"
	assert_output_contains "ready"
	assert_output_contains "nas-linux"
	assert_output_contains "backup-unreachable"
}

@test "fleet scan --json starts with a brace" {
	export RACCOON_SCAN_HOSTS="192.168.1.10"
	run bash "$SCRIPT_DIR/bin/fleet.sh" scan --json --user mario
	assert_audit_exit
	[[ "$output" == '{'* ]]
}

@test "fleet scan --add appends only ready hosts to fleet.conf" {
	export RACCOON_SCAN_HOSTS="192.168.1.10 nas-linux backup-unreachable"
	run bash "$SCRIPT_DIR/bin/fleet.sh" scan --user mario --add
	assert_audit_exit
	run cat "$HOME/.raccoon/fleet.conf"
	assert_output_contains "mario@192.168.1.10"
	[[ "$output" != *"nas-linux"* ]]
	[[ "$output" != *"unreachable"* ]]
}

@test "fleet scan non-interactive input does not consume stdin or add" {
	# Not a tty: the prompt/read is skipped, answer stays "n", nothing is added.
	export RACCOON_SCAN_HOSTS="192.168.1.10"
	run bash "$SCRIPT_DIR/bin/fleet.sh" scan --user mario <<< "y"
	assert_audit_exit
	assert_output_contains "Not added"
	[[ ! -f "$HOME/.raccoon/fleet.conf" ]] || ! grep -q "mario@192.168.1.10" "$HOME/.raccoon/fleet.conf"
}

@test "fleet scan with no candidates exits 0 with a message" {
	export RACCOON_SCAN_HOSTS=" "
	run bash "$SCRIPT_DIR/bin/fleet.sh" scan
	assert_audit_exit
	assert_output_contains "No hosts"
}

# --- groups & bulk run -------------------------------------------------------

@test "fleet group list with no groups reports none" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" group list
	assert_audit_exit
	assert_output_contains "No groups"
}

@test "fleet group add then list shows group and members" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" group add office mario@192.168.1.10
	assert_audit_exit
	run bash "$SCRIPT_DIR/bin/fleet.sh" group list
	assert_output_contains "office"
	run bash "$SCRIPT_DIR/bin/fleet.sh" group list office
	assert_output_contains "mario@192.168.1.10"
}

@test "fleet group remove deletes the whole group" {
	printf 'office\tmario@192.168.1.10\n' > "$HOME/.raccoon/fleet-groups.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" group remove office
	assert_audit_exit
	run bash "$SCRIPT_DIR/bin/fleet.sh" group list
	assert_output_contains "No groups"
}

@test "fleet audit --group audits only group members" {
	printf '%s\n' "a@192.168.1.1" "b@192.168.1.2" "c@192.168.1.3" > "$HOME/.raccoon/fleet.conf"
	printf 'g\ta@192.168.1.1\ng\tb@192.168.1.2\n' > "$HOME/.raccoon/fleet-groups.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit --group g
	assert_audit_exit
	assert_output_contains "a@192.168.1.1"
	assert_output_contains "b@192.168.1.2"
	[[ "$output" != *"c@192.168.1.3"* ]]
}

@test "fleet run executes a command on each group member" {
	printf '%s\n' "mario@192.168.1.10" "luca@192.168.1.11" > "$HOME/.raccoon/fleet.conf"
	printf 'office\tmario@192.168.1.10\noffice\tluca@192.168.1.11\n' > "$HOME/.raccoon/fleet-groups.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" run --group office -- whoami
	assert_audit_exit
	assert_output_contains "=== mario@192.168.1.10 ==="
	assert_output_contains "=== luca@192.168.1.11 ==="
	assert_output_contains "RAN:whoami"
}

@test "fleet run with no command shows usage" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" run --group office
	assert_failure
	assert_output_contains "Usage: rcc fleet run"
}

@test "fleet unknown subcommand prints help and returns non-zero" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" bogus
	assert_failure
	assert_output_contains "Usage: rcc fleet"
}

# ─── host:port parsing ──────────────────────────────────────────────────
#
# `case *:[0-9]*` read any colon-then-digit as a port, so every bare IPv6
# literal became a host that does not exist on a port nobody asked for. ssh is
# recorded through the RACCOON_SSH seam — nothing here touches the network.

_record_ssh() {
	cat > "$HOME/recordssh" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$SSH_LOG"
echo ok
MOCK
	chmod +x "$HOME/recordssh"
	export SSH_LOG="$HOME/ssh.log"
	: > "$SSH_LOG"
	export RACCOON_SSH="$HOME/recordssh"
}

# Write one host line, run `fleet status`, and hand back what ssh was called with.
_status_for() {
	_record_ssh
	printf '%s\n' "$1" > "$HOME/.raccoon/fleet.conf"
	bash "$SCRIPT_DIR/bin/fleet.sh" status > /dev/null 2>&1 || true
	cat "$SSH_LOG"
}

@test "fleet: a bare IPv6 literal is a host, not a host and a port" {
	run _status_for "fe80::1"
	assert_output_contains " fe80::1"
	[[ "$output" != *"-p 1"* ]]
	[[ "$output" != *"fe80: "* ]]
}

@test "fleet: a bare global IPv6 literal keeps all of its colons" {
	run _status_for "2001:db8::1"
	assert_output_contains " 2001:db8::1"
	[[ "$output" != *"-p "* ]]
}

@test "fleet: a bracketed IPv6 literal loses the brackets and gains no port" {
	run _status_for "[2001:db8::1]"
	assert_output_contains " 2001:db8::1"
	[[ "$output" != *"-p "* ]]
	[[ "$output" != *"["* ]]
}

@test "fleet: the loopback literal survives" {
	run _status_for "::1"
	assert_output_contains " ::1"
	[[ "$output" != *"-p "* ]]
}

@test "fleet: a bracketed IPv6 literal with a port keeps both" {
	run _status_for "[2001:db8::1]:22"
	assert_output_contains "-p 22"
	assert_output_contains " 2001:db8::1"
	[[ "$output" != *"["* ]]
}

@test "fleet: a hostname with a port still splits" {
	run _status_for "mac.local:2222"
	assert_output_contains "-p 2222"
	assert_output_contains " mac.local"
}

@test "fleet: a hostname with hyphens is not mistaken for anything" {
	run _status_for "my-host-01"
	assert_output_contains " my-host-01"
	[[ "$output" != *"-p "* ]]
}

@test "fleet: a port out of range is not a port" {
	run _status_for "mac.local:99999"
	[[ "$output" != *"-p "* ]]
	assert_output_contains " mac.local:99999"
}

@test "fleet: port zero is not a port either" {
	run _status_for "mac.local:0"
	[[ "$output" != *"-p "* ]]
}

@test "fleet: a non-numeric port is not a port" {
	run _status_for "mac.local:ssh"
	[[ "$output" != *"-p "* ]]
	assert_output_contains " mac.local:ssh"
}

@test "fleet: an unclosed bracket invents nothing" {
	run _status_for "[2001:db8::1:22"
	[[ "$output" != *"-p "* ]]
	assert_output_contains "[2001:db8::1:22"
}

@test "fleet: a user@ prefix survives on an IPv6 literal" {
	run _status_for "mario@2001:db8::1"
	assert_output_contains " mario@2001:db8::1"
	[[ "$output" != *"-p "* ]]
}

# The box drew as ┌������┐: `printf '%*s' 48 '' | tr ' ' '─'` substitutes
# bytes, and ─ is three of them in UTF-8, so every space became a third of a
# character. Sourcing fleet.sh runs main, and main without a subcommand starts
# an audit over SSH, so the box function is extracted and run on its own.
@test "fleet: the box is drawn in characters, not in bytes" {
	local fn out
	fn="$(sed -n '/^_fleet_box_line() {/,/^}/p' "$SCRIPT_DIR/bin/fleet.sh")"
	[[ -n "$fn" ]] || { echo "_fleet_box_line not found" >&2; false; }

	out="$(LC_ALL=C bash -c "
		$fn
		line=\"\"; for ((i = 0; i < 48; i++)); do line+='─'; done
		echo \"┌\${line}┐\"
		_fleet_box_line '1 hosts · 5 parallel connections'
		echo \"└\${line}┘\"
	")"

	# Measured in characters, not bytes: awk's length() under LC_ALL=C counts
	# bytes, which is the very mistake being tested for.
	command -v python3 > /dev/null || skip "python3 not available"
	local widths
	widths="$(printf '%s\n' "$out" | python3 -c '
import sys
print(len({len(line.rstrip(chr(10))) for line in sys.stdin if line.strip()}))
')"
	[[ "$widths" == "1" ]] || {
		echo "the box edges do not line up:" >&2
		printf '%s\n' "$out" >&2
		false
	}
	[[ "$out" != *"�"* ]] || { echo "broken characters: $out" >&2; false; }
}

@test "fleet: no line is built by substituting bytes" {
	# tr works on bytes: any box character fed to it comes out in pieces.
	# Comment lines are skipped: the fix explains the idiom by quoting it.
	run grep -vE "^[[:space:]]*#" "$SCRIPT_DIR/bin/fleet.sh"
	run grep -nE "tr ' ' '[^ -~]" <<< "$output"
	[[ "$status" -ne 0 ]] || {
		echo "a rule is still built byte-wise: $output" >&2
		false
	}
}
