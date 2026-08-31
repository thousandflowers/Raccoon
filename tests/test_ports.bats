load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "ports: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --help
    assert_success
}

@test "ports: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/ports.sh" -h
    assert_success
}

@test "ports: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --help
    assert_output_contains "Usage"
}

@test "ports: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ports: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/ports.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ports: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/ports.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "ports: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/ports.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# ─── parsing ────────────────────────────────────────────────────────────
#
# lsof output is not reproducible on a real machine, so every test below runs
# against a fixed fake one. The `ps` stub is empty unless a test needs name
# resolution, which leaves the process name as lsof reported it — that is the
# path the escaping has to survive.

_stub_lsof() {
	STUB="${BATS_TEST_TMPDIR}/stub"
	mkdir -p "$STUB"
	{
		echo '#!/bin/bash'
		echo "cat <<'LSOF'"
		printf 'COMMAND     PID                    USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME\n'
		cat
		echo 'LSOF'
	} > "$STUB/lsof"
	chmod +x "$STUB/lsof"
	printf '#!/bin/bash\nexit 0\n' > "$STUB/ps"
	chmod +x "$STUB/ps"
}

_stub_ps() {
	printf '#!/bin/bash\ncat <<PS\n%s\nPS\n' "$1" > "$STUB/ps"
	chmod +x "$STUB/ps"
}

_json() { PATH="$STUB:$PATH" bash "$SCRIPT_DIR/bin/ports.sh" --json; }
_text() { NO_COLOR=1 PATH="$STUB:$PATH" bash "$SCRIPT_DIR/bin/ports.sh"; }

assert_valid_json() {
	command -v python3 > /dev/null || skip "python3 not available"
	printf '%s' "$1" | python3 -m json.tool > /dev/null
}

@test "ports: a connected IPv4 socket reports the local port, not the peer's" {
	_stub_lsof <<-'EOF'
		rapportd  1630 someone   10u  IPv4 0x23d8      0t0  TCP 172.20.10.3:51794->160.79.104.10:443 (ESTABLISHED)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"port": "51794"'
	[[ "$output" != *'"port": "443"'* ]]
	assert_output_contains '"address": "172.20.10.3:51794"'
}

@test "ports: a connected IPv6 socket reports the local port, not a hextet" {
	_stub_lsof <<-'EOF'
		rapportd  1630 someone   11u  IPv6 0xe144      0t0  TCP [fe80:e::479:7b38:ef37:a217]:56122->[fe80:e::3ccd:40ff:fe37:9664]:54343 (ESTABLISHED)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"port": "56122"'
	[[ "$output" != *'"port": "479"'* ]]
	[[ "$output" != *'"port": "54343"'* ]]
}

@test "ports: the table agrees with the JSON on a connected IPv6 socket" {
	_stub_lsof <<-'EOF'
		rapportd  1630 someone   11u  IPv6 0xe144      0t0  TCP [fe80:e::479:7b38:ef37:a217]:56122->[fe80:e::3ccd:40ff:fe37:9664]:54343 (ESTABLISHED)
	EOF
	run _text
	assert_success
	assert_output_contains "56122"
	[[ "$output" != *"| 479 "* ]]
}

@test "ports: a listening socket has no arrow and keeps its port" {
	_stub_lsof <<-'EOF'
		ControlCe 1631 someone   12u  IPv4 0xaaaa      0t0  TCP *:7000 (LISTEN)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"port": "7000"'
	assert_output_contains '"state": "LISTEN"'
	assert_output_contains '"address": "*:7000"'
}

@test "ports: loopback and wildcard are distinguishable in the address" {
	_stub_lsof <<-'EOF'
		privately 2100 someone   12u  IPv4 0xaaaa      0t0  TCP 127.0.0.1:8765 (LISTEN)
		publicly  2101 someone   13u  IPv4 0xbbbb      0t0  TCP *:8766 (LISTEN)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"address": "127.0.0.1:8765"'
	assert_output_contains '"address": "*:8766"'
}

@test "ports: a command name carrying \\x20 still parses as JSON" {
	_stub_lsof <<-'EOF'
		Adobe\x20 2000 someone   13u  IPv4 0xbbbb      0t0  TCP 127.0.0.1:15292 (LISTEN)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"process": "Adobe"'
}

@test "ports: a command name with a quote in it still parses as JSON" {
	_stub_lsof <<-'EOF'
		we"ird    2001 someone   15u  IPv4 0xdddd      0t0  TCP 127.0.0.1:9001 (LISTEN)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
}

@test "ports: a command name with a backslash in it still parses as JSON" {
	_stub_lsof <<-'EOF'
		back\slash 2002 someone  16u  IPv4 0xeeee      0t0  TCP 127.0.0.1:9002 (LISTEN)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
}

@test "ports: an unbound socket keeps its star and sorts after the numbers" {
	_stub_lsof <<-'EOF'
		sharingd  1706 someone   14u  IPv4 0xcccc      0t0  UDP *:*
		listening 1707 someone   15u  IPv4 0xdddd      0t0  TCP *:22 (LISTEN)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"port": "*"'
	run _text
	assert_success
	[[ "$(printf '%s' "$output" | grep -n '| 22 ' | cut -d: -f1)" -lt \
	   "$(printf '%s' "$output" | grep -n '| \* ' | cut -d: -f1)" ]]
}

@test "ports: no lsof output gives an empty JSON array" {
	STUB="${BATS_TEST_TMPDIR}/stub"
	mkdir -p "$STUB"
	printf '#!/bin/bash\nexit 0\n' > "$STUB/lsof"
	printf '#!/bin/bash\nexit 0\n' > "$STUB/ps"
	chmod +x "$STUB/lsof" "$STUB/ps"
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output "[]"
}

@test "ports: no lsof output says so in the table" {
	STUB="${BATS_TEST_TMPDIR}/stub"
	mkdir -p "$STUB"
	printf '#!/bin/bash\nexit 0\n' > "$STUB/lsof"
	printf '#!/bin/bash\nexit 0\n' > "$STUB/ps"
	chmod +x "$STUB/lsof" "$STUB/ps"
	run _text
	assert_success
	assert_output_contains "No ports found"
}

@test "ports: the pid resolves the name lsof truncated" {
	_stub_lsof <<-'EOF'
		identitys 1672 someone   14u  IPv4 0xcccc      0t0  TCP *:1234 (LISTEN)
	EOF
	_stub_ps "1672 /usr/libexec/identityservicesd"
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"process": "identityservicesd"'
	assert_output_contains '"pid": 1672'
}

@test "ports: a pid ps cannot resolve keeps the name lsof gave" {
	_stub_lsof <<-'EOF'
		orphaned  9999 someone   14u  IPv4 0xcccc      0t0  TCP *:1235 (LISTEN)
	EOF
	run _json
	assert_success
	assert_valid_json "$output"
	assert_output_contains '"process": "orphaned"'
}

@test "ports: two sockets that differ only in state both survive the sort" {
	_stub_lsof <<-'EOF'
		rapportd  1630 someone   10u  IPv4 0xaaaa      0t0  TCP *:56122 (LISTEN)
		rapportd  1630 someone   11u  IPv6 0xbbbb      0t0  TCP [fe80::1]:56122->[fe80::2]:54343 (ESTABLISHED)
	EOF
	run _text
	assert_success
	assert_output_contains "LISTEN"
	assert_output_contains "ESTABLISHED"
	[[ "$(printf '%s' "$output" | grep -c '56122')" -eq 2 ]]
}

@test "ports: the table does not collapse unrelated sockets" {
	_stub_lsof <<-'EOF'
		alpha     2001 someone   10u  IPv4 0xaaaa      0t0  TCP *:8001 (LISTEN)
		beta      2002 someone   11u  IPv4 0xbbbb      0t0  TCP *:8002 (LISTEN)
		gamma     2003 someone   12u  IPv4 0xcccc      0t0  TCP *:8003 (LISTEN)
	EOF
	run _text
	assert_success
	[[ "$(printf '%s' "$output" | grep -c '^| 800')" -eq 3 ]]
}
