load test_helper
setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

# `softwareupdate -l` takes over seven minutes on a fresh GitHub runner and its
# answer is meaningless there: the pending updates of a machine destroyed ten
# minutes later tell nobody anything. It is 14m43s of a 16m49s CI run, paid
# twice per release — once for the PR, once inside the Release workflow.
#
# The skip must never report "Up to date". Saying the updates are fine without
# having looked is the exact defect this repository spent a night removing.

@test "audit: the software update check can be skipped" {
    RCC_SKIP_SOFTWARE_UPDATE=1 run bash "$SCRIPT_DIR/bin/audit.sh" --json
    assert_audit_exit
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = [r for r in d["results"] if "Software Update" in r.get("name", "")]
assert rows, "the check disappeared entirely"
'
}

@test "audit: a skipped update check never claims the Mac is up to date" {
    RCC_SKIP_SOFTWARE_UPDATE=1 run bash "$SCRIPT_DIR/bin/audit.sh" --json
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in d["results"]:
    if "Software Update" in r.get("name", ""):
        assert r["status"] != "pass", f"claimed pass without looking: {r}"
        assert "not checked" in (r.get("value","") + r.get("name","")).lower(), r
'
}

@test "audit: skipping it does not run softwareupdate at all" {
    # A fake softwareupdate that fails loudly if called: if the skip works,
    # nothing invokes it and the audit still finishes.
    mkdir -p "$HOME/fakebin"
    printf '#!/bin/sh\necho CALLED-SOFTWAREUPDATE >&2\nexit 3\n' > "$HOME/fakebin/softwareupdate"
    chmod +x "$HOME/fakebin/softwareupdate"
    PATH="$HOME/fakebin:$PATH" RCC_SKIP_SOFTWARE_UPDATE=1 run bash "$SCRIPT_DIR/bin/audit.sh" --json
    [[ "$output" != *"CALLED-SOFTWAREUPDATE"* ]] || { echo "it ran anyway"; return 1; }
}

@test "audit: without the variable the check still runs normally" {
    # Explicitly unset, not merely absent: CI sets this at workflow level, so a
    # test that assumed a clean environment would fail there and nowhere else.
    unset RCC_SKIP_SOFTWARE_UPDATE
    run bash "$SCRIPT_DIR/bin/audit.sh" --json
    assert_audit_exit
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = [r for r in d["results"] if "Software Update" in r.get("name","")]
assert rows and "not checked" not in rows[0].get("value","").lower(), rows
'
}
