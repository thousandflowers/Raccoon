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

# --- measured, not read: the findings of 2026-09-02 ---------------------------

@test "network: addresses come from every interface ifconfig lists, not a fixed nine" {
	run bash "$SCRIPT_DIR/bin/network.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, subprocess, sys
d = json.load(sys.stdin)
listed = {i["name"] for i in d["interfaces"]}
# Every interface with a non-link-local address, as ifconfig sees it.
truth = set()
for iface in subprocess.run(["ifconfig", "-l"], capture_output=True, text=True).stdout.split():
    out = subprocess.run(["ifconfig", iface], capture_output=True, text=True).stdout
    for line in out.splitlines():
        f = line.split()
        if len(f) > 1 and f[0] in ("inet", "inet6") and not f[1].startswith("fe80") and not f[1].startswith("169.254"):
            truth.add(iface)
assert listed == truth, (listed, truth)
for i in d["interfaces"]:
    assert i["kind"] != "LinkLocal", i
    assert i["kind"] != "Other" or ":" not in i["address"], i
'
}

@test "network: an iPhone hotspot address is private space, not WireGuard" {
	# The function alone, on the ranges that used to be misread.
	run bash -c 'source "$1"; categorize_interface 172.20.10.3; categorize_interface 172.31.255.1; categorize_interface 172.32.0.1; categorize_interface 2a02:b027::1; categorize_interface fd7a:115c:a1e0::1; categorize_interface 100.100.1.1; categorize_interface 10.0.0.5' _ <(sed -n '/^categorize_interface()/,/^}/p' "$SCRIPT_DIR/bin/network.sh")
	assert_success
	[[ "${lines[0]}" == "Private" ]]
	[[ "${lines[1]}" == "Private" ]]
	[[ "${lines[2]}" == "Public" ]]
	[[ "${lines[3]}" == "Public" ]]
	[[ "${lines[4]}" == "Tailscale" ]]
	[[ "${lines[5]}" == "CGNAT" ]]
	[[ "${lines[6]}" == "Private" ]]
}

@test "network: a firewall tool that cannot run is 'unknown', never 'disabled'" {
	command -v sandbox-exec >/dev/null 2>&1 || skip "sandbox-exec not available"
	run sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/libexec/ApplicationFirewall/socketfilterfw"))' bash "$SCRIPT_DIR/bin/network.sh" --json
	assert_success
	[[ "$output" == *'"application": "unknown"'* ]]
}

@test "network: system proxies from System Settings are read, not only the environment" {
	local shim="$HOME/shim"
	mkdir -p "$shim"
	cat > "$shim/scutil" <<'SH'
#!/bin/bash
case "$1" in
	--proxy) printf '<dictionary> {\n  HTTPEnable : 1\n  HTTPProxy : 127.0.0.1\n  HTTPPort : 12334\n  HTTPSEnable : 0\n  SOCKSEnable : 0\n  ProxyAutoConfigEnable : 0\n}\n' ;;
	--dns) printf 'resolver #1\n  nameserver[0] : 1.1.1.1\n' ;;
	--nc) printf 'Available network connection services in the current set (*=enabled):\n' ;;
	*) exit 1 ;;
esac
SH
	chmod +x "$shim/scutil"
	PATH="$shim:$PATH" run bash "$SCRIPT_DIR/bin/network.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert {"name": "system HTTP", "value": "127.0.0.1:12334"} in d["proxies"], d["proxies"]
assert d["dns"] == ["1.1.1.1"], d["dns"]
'
}

@test "network: without /usr/sbin it is 'not checked', not an empty machine" {
	run env -i PATH=/usr/bin:/bin HOME="$HOME" bash "$SCRIPT_DIR/bin/network.sh" --json
	[[ "$status" -eq 3 ]]
	[[ "$output" == *"Not checked"* ]]
	[[ "$output" != *'"interfaces"'* ]]
}
