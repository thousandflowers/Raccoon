load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "battery: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --help
    assert_success
}

@test "battery: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/battery.sh" -h
    assert_success
}

@test "battery: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --help
    assert_output_contains "Usage"
}

@test "battery: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "battery: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/battery.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "battery: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/battery.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "battery: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/battery.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}



# ─── no battery ─────────────────────────────────────────────────────────
#
# A Mac mini, a Studio, an iMac and a CI runner have no battery. pmset prints
# no percentage and system_profiler no battery block, which used to kill the
# script under set -euo pipefail before it could say so: exit 1 and not one
# line of output, in text mode as well as --json. These stubs reproduce that
# machine on any machine, so the case is exercised here and not only on CI.

_stub_no_battery() {
	STUB="${BATS_TEST_TMPDIR}/nobat"
	mkdir -p "$STUB"
	printf '#!/bin/bash\nexit 1\n' > "$STUB/pmset"
	printf '#!/bin/bash\nexit 1\n' > "$STUB/system_profiler"
	chmod +x "$STUB/pmset" "$STUB/system_profiler"
}

@test "battery: no battery is a result, not a failure" {
	_stub_no_battery
	run env PATH="$STUB:$PATH" bash "$SCRIPT_DIR/bin/battery.sh"
	assert_success
	assert_output_contains "No battery"
}

@test "battery: no battery still prints JSON, and says the battery is absent" {
	command -v python3 > /dev/null || skip "python3 not available"
	_stub_no_battery
	run env PATH="$STUB:$PATH" bash "$SCRIPT_DIR/bin/battery.sh" --json
	assert_success
	printf '%s' "$output" | python3 -m json.tool > /dev/null
	assert_output_contains '"present": false'
}

@test "battery: an absent battery reports null, not zero" {
	_stub_no_battery
	run env PATH="$STUB:$PATH" bash "$SCRIPT_DIR/bin/battery.sh" --json
	assert_success
	assert_output_contains '"cycle_count": null'
	assert_output_contains '"charge_percent": null'
	# A zero here would read as a new battery at a flat charge, which is the
	# opposite of what is true.
	[[ "$output" != *'"cycle_count": 0'* ]]
}

@test "battery: --json always carries present, whether or not there is one" {
	run bash "$SCRIPT_DIR/bin/battery.sh" --json
	assert_success
	assert_output_contains '"present":'
}

# SPPowerDataType prints "Charging:" twice, for the battery and for the AC
# charger. Taking both made the record two lines, and every field after
# charging was dropped: this Mac reported "Fully Charged: No" at 100%.
@test "battery: a duplicated Charging line does not truncate the record" {
	command -v python3 > /dev/null || skip "python3 not available"
	STUB="${BATS_TEST_TMPDIR}/dup"
	mkdir -p "$STUB"
	cat > "$STUB/system_profiler" <<-'SP'
		#!/bin/bash
		cat <<-'OUT'
		          Cycle Count: 42
		          Condition: Normal
		          Maximum Capacity: 91%
		          Charging: No
		          Fully Charged: Yes
		      AC Charger Information:
		          Charging: No
		OUT
	SP
	printf '#!/bin/bash\necho "  99%%; discharging"\n' > "$STUB/pmset"
	chmod +x "$STUB/system_profiler" "$STUB/pmset"
	run env PATH="$STUB:$PATH" bash "$SCRIPT_DIR/bin/battery.sh" --json
	assert_success
	printf '%s' "$output" | python3 -m json.tool > /dev/null
	assert_output_contains '"fully_charged": true'
	assert_output_contains '"cycle_count": 42'
}
