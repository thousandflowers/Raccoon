#!/usr/bin/env bats
# Tests for `rcc startup --clean` — orphaned launch-agent detection/removal.
# Only ~/Library/LaunchAgents is ever touched; a temp HOME keeps it isolated.

load test_helper

setup() {
	setup_raccoon_env
	mkdir -p "$HOME/Library/LaunchAgents"
}

teardown() {
	teardown_raccoon_env
}

# Write a minimal launch-agent plist pointing at $2 into $HOME/Library/LaunchAgents.
_make_agent() {
	local label="$1" exe="$2"
	cat > "$HOME/Library/LaunchAgents/${label}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${label}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${exe}</string>
	</array>
</dict>
</plist>
PLIST
}

@test "startup --clean with no launch agents reports none and exits 0" {
	run bash "$SCRIPT_DIR/bin/startup.sh" --clean
	assert_success
	assert_output_contains "Nessun launch agent orfano"
}

@test "startup --clean detects an agent pointing at a missing binary" {
	_make_agent "com.test.orphan" "/nonexistent/binary"
	# Decline the global prompt so nothing is removed; detection still reported.
	run bash "$SCRIPT_DIR/bin/startup.sh" --clean <<< "n"
	assert_success
	assert_output_contains "com.test.orphan.plist"
	assert_output_contains "/nonexistent/binary"
	# Declined -> the plist is still there.
	[[ -f "$HOME/Library/LaunchAgents/com.test.orphan.plist" ]]
}

@test "startup --clean treats an existing binary as not orphaned" {
	_make_agent "com.test.live" "/usr/bin/true"
	run bash "$SCRIPT_DIR/bin/startup.sh" --clean
	assert_success
	assert_output_contains "Nessun launch agent orfano"
}

@test "startup --clean dry run (decline each) removes nothing" {
	_make_agent "com.test.orphan" "/nonexistent/binary"
	# Proceed globally (y), then decline the per-item prompt (n).
	run bash "$SCRIPT_DIR/bin/startup.sh" --clean <<< $'y\nn'
	assert_success
	assert_output_contains "skip"
	# Nothing was removed.
	[[ -f "$HOME/Library/LaunchAgents/com.test.orphan.plist" ]]
}
