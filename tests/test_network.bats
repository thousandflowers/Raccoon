load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "network: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/network.sh" --help
    assert_success
}

@test "network: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/network.sh" -h
    assert_success
}

@test "network: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/network.sh" --help
    assert_output_contains "Usage"
}

@test "network: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/network.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "network: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/network.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "network: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/network.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "network: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/network.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# ─── listening ports ────────────────────────────────────────────────────
#
# lsof and ping are stubbed so the section is deterministic and nothing leaves
# the machine. The point of the third row: it carries an arrow *and* the word
# LISTEN, which real lsof never writes together. It is there to show that the
# port now comes from the shape of the address, not from the `grep LISTEN` that
# used to be the only thing keeping this correct.

_stub_network() {
	STUB="${BATS_TEST_TMPDIR}/stub"
	mkdir -p "$STUB"
	{
		echo '#!/bin/bash'
		echo "cat <<'LSOF'"
		printf 'COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME\n'
		cat
		echo 'LSOF'
	} > "$STUB/lsof"
	printf '#!/bin/bash\nexit 1\n' > "$STUB/ping"
	chmod +x "$STUB/lsof" "$STUB/ping"
}

_network_ports() {
	NO_COLOR=1 PATH="$STUB:$PATH" bash "$SCRIPT_DIR/bin/network.sh" 2>/dev/null |
		sed -n '/Listening Ports/,/\[3\/10\]/p'
}

@test "network: a listening IPv4 port is reported" {
	_stub_network <<-'EOF'
		airplayd  100 someone 12u IPv4 0xaaaa 0t0 TCP *:7000 (LISTEN)
	EOF
	run _network_ports
	assert_output_contains "7000"
	assert_output_contains "AirPlay"
}

@test "network: a listening IPv6 port is the port, not a hextet" {
	_stub_network <<-'EOF'
		proxyd    101 someone 13u IPv6 0xbbbb 0t0 TCP [fe80:e::479:7b38:ef37:a217]:8080 (LISTEN)
	EOF
	run _network_ports
	assert_output_contains "8080"
	assert_output_contains "HTTP-Proxy"
	[[ "$output" != *"479"* ]]
}

@test "network: a connected socket would give its local port, not the peer's" {
	_stub_network <<-'EOF'
		socksd    102 someone 14u IPv4 0xcccc 0t0 TCP 172.20.10.3:1080->160.79.104.10:443 (LISTEN)
	EOF
	run _network_ports
	assert_output_contains "1080"
	assert_output_contains "SOCKS5"
	[[ "$output" != *"V2Ray"* ]]
}
