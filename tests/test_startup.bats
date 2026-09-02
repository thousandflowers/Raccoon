load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "startup: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --help
    assert_success
}

@test "startup: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/startup.sh" -h
    assert_success
}

@test "startup: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --help
    assert_output_contains "Usage"
}

@test "startup: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "startup: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/startup.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "startup: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/startup.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "startup: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/startup.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# --- measured, not read: the findings of 2026-09-02 ---------------------------

@test "startup: a user agent is reported by launchd's Label, not by its filename" {
	mkdir -p "$HOME/Library/LaunchAgents"
	# The filename says Invoker; the Label says Scheduler. launchctl takes the Label.
	cat > "$HOME/Library/LaunchAgents/com.example.GC.Invoker-1.0.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>Label</key><string>com.example.GC.Scheduler-1.0</string>
	<key>ProgramArguments</key><array><string>/usr/bin/true</string></array>
</dict></plist>
PLIST
	run bash "$SCRIPT_DIR/bin/startup.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
[a] = [a for a in d["user_agents"] if a["file"].endswith("com.example.GC.Invoker-1.0.plist")]
assert a["label"] == "com.example.GC.Scheduler-1.0", a
assert a["name"] == "GC.Invoker-1.0", a
assert a["loaded"] is False, a  # never loaded: the test only wrote the file
'
}

@test "startup: running services are the ones with a process, and never more than the loaded ones" {
	run bash "$SCRIPT_DIR/bin/startup.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, subprocess, sys
d = json.load(sys.stdin)["counts"]
rows = subprocess.run(["launchctl", "list"], capture_output=True, text=True).stdout.splitlines()[1:]
with_pid = sum(1 for r in rows if not r.startswith("-"))
assert d["running_services"] <= d["loaded_services"], d
# launchctl list drifts by a few entries between two calls; the old number was 3x off.
assert abs(d["running_services"] - with_pid) < 0.2 * max(with_pid, 1), (d, with_pid)
assert d["system_agents_loaded"] <= d["system_agents"], d
'
}

@test "startup: a refused System Events is 'not checked', not zero login items" {
	local shim="$HOME/shim"
	mkdir -p "$shim"
	cat > "$shim/osascript" <<'SH'
#!/bin/bash
echo "execution error: Not authorized to send Apple events to System Events. (-1743)" >&2
exit 1
SH
	chmod +x "$shim/osascript"
	run env PATH="$shim:$PATH" bash "$SCRIPT_DIR/bin/startup.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["login_items"] == []
assert "Not authorized" in d["login_items_error"], d["login_items_error"]
'
	run env PATH="$shim:$PATH" bash "$SCRIPT_DIR/bin/startup.sh"
	assert_success
	assert_output_contains "not checked"
	[[ "$output" != *"no login items configured"* ]]
}

@test "startup: background items exclude Apple's own and the apps a person has open" {
	run bash "$SCRIPT_DIR/bin/startup.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for b in d["background_items"]:
    assert not b["label"].startswith("com.apple."), b
    assert not b["label"].startswith("application."), b
    assert b["pid"] is None or isinstance(b["pid"], int), b
'
}
