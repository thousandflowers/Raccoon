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
	*"bash -s"*) printf '{\n  "pass": 25,\n  "warning": 1,\n  "fail": 0,\n  "results": [\n    {"status": "warn", "category": "Net", "name": "Sharing", "value": "1"}\n  ]\n}\n'; exit 0 ;;
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
	assert_success
	assert_output_contains "Nessun host"
}

@test "fleet add then list shows the host" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" add mario@192.168.1.10
	assert_success
	run bash "$SCRIPT_DIR/bin/fleet.sh" list
	assert_success
	assert_output_contains "mario@192.168.1.10"
}

@test "fleet remove confirmed deletes the host" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" remove mario@192.168.1.10 <<< "y"
	assert_success
	run bash "$SCRIPT_DIR/bin/fleet.sh" list
	assert_output_contains "Nessun host"
}

@test "fleet status shows reachable hosts with a check mark" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" status
	assert_success
	assert_output_contains "✓"
}

@test "fleet status marks unreachable hosts with a cross" {
	printf '%s\n' "backup@unreachable.host" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" status
	assert_success
	assert_output_contains "✗"
}

@test "fleet audit aggregates reachable and unreachable hosts" {
	printf '%s\n' "mario@192.168.1.10" "admin@office.example.com" "backup@unreachable.host" \
		> "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit
	assert_success
	assert_output_contains "2/3 host raggiunti"
}

@test "fleet audit --json starts with a brace" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit --json
	assert_success
	[[ "$output" == '{'* ]]
}

@test "fleet audit --report writes a Markdown report" {
	printf '%s\n' "mario@192.168.1.10" > "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit --report "$HOME/fleet.md"
	assert_success
	[[ -f "$HOME/fleet.md" ]]
	grep -q "Fleet Audit" "$HOME/fleet.md"
}

@test "fleet audit --parallel 1 processes all hosts in order" {
	printf '%s\n' "a@192.168.1.1" "b@192.168.1.2" "c@192.168.1.3" \
		> "$HOME/.raccoon/fleet.conf"
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit --parallel 1
	assert_success
	assert_output_contains "3/3 host raggiunti"
}

@test "fleet audit with no config exits 0 with a message" {
	run bash "$SCRIPT_DIR/bin/fleet.sh" audit
	assert_success
	assert_output_contains "Nessun host configurato"
}
