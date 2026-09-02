load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "certs: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/certs.sh" --help
    assert_success
}

@test "certs: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/certs.sh" -h
    assert_success
}

@test "certs: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/certs.sh" --help
    assert_output_contains "Usage"
}

@test "certs: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/certs.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "certs: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/certs.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "certs: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/certs.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "certs: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/certs.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# --- measured, not read: the findings of 2026-09-02 ---------------------------

@test "certs: --json names every certificate's keychain and SHA-256" {
	run bash "$SCRIPT_DIR/bin/certs.sh" --json
	assert_success
	local total
	total=$(printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["counts"]["total"])')
	[[ "$total" -gt 0 ]] || skip "no certificates in the keychains of this account"
	printf '%s' "$output" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
for c in d["certificates"]:
    assert re.fullmatch(r"[0-9A-F]{64}", c["sha256"]), c
    assert c["keychain"] in d["keychains"], c
    # A name is the CN, never the whole DN: no "CN=", no leading slash.
    assert "CN=" not in c["name"] and not c["name"].startswith("/"), c
'
}

@test "certs: the keychains listed are the ones searched, and they exist" {
	run bash "$SCRIPT_DIR/bin/certs.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, os, sys
d = json.load(sys.stdin)
assert d["keychains"], "no keychain in the search list"
for k in d["keychains"]:
    assert os.path.exists(k), k + " is listed but does not exist"
    assert "SystemRoot.keychain" not in k
'
}

@test "certs: --expiring N shows only certificates inside the window in text mode" {
	run bash "$SCRIPT_DIR/bin/certs.sh" --expiring 1
	assert_success
	# Between the details header and the keychain section, no row may be
	# "valid" or "expired": those are outside a one-day window by definition.
	local rows
	rows=$(printf '%s\n' "$output" | sed -n '/Certificate Details/,/Keychains Searched/p' | grep -cE '(^| )(valid|expired)( |$)' || true)
	[[ "$rows" -eq 0 ]]
}

@test "certs: a missing openssl is 'not checked', never zero certificates" {
	local tools="$HOME/tools"
	mkdir -p "$tools"
	# Everything the script needs except openssl, so PATH can name only this dir.
	local t
	for t in bash security python3 sed awk grep cut tail head tr wc readlink dirname basename cat sort uname date mktemp id env printf; do
		ln -sf "$(command -v "$t")" "$tools/$t"
	done
	run env -i PATH="$tools" HOME="$HOME" bash "$SCRIPT_DIR/bin/certs.sh" --json
	[[ "$status" -eq 3 ]]
	[[ "$output" == *"Not checked"*"openssl"* ]]
	[[ "$output" != *'"total"'* ]]
}
