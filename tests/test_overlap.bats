load test_helper

# The fixture is a fake filesystem: every manager root lives under $FIX (or
# under the test $HOME, which test_helper already redirects). Nothing here
# touches the real machine, so these tests are identical on macOS and Linux.

setup() {
    setup_raccoon_env

    FIX="${BATS_TMPDIR}/overlap-fix-${BATS_TEST_NUMBER}-$$"
    rm -rf "$FIX"
    _build_fixture

    export RCC_OVERLAP_ROOT="$FIX"
    export RCC_OVERLAP_NPM_PREFIX="$FIX/npm"

    # Scanned separately from the real $PATH so the script keeps finding its
    # own tools (awk, sort) while walking a fake PATH.
    export RCC_OVERLAP_PATH="\
$FIX/opt/homebrew/bin:\
$FIX/opt/local/bin:\
$FIX/nix-bin:\
$HOME/.nix-profile/bin:\
$HOME/go/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
$HOME/.local/share/mise/shims:\
$HOME/.local/share/mise/installs/node/22.0.0/bin:\
$FIX/npm/bin:\
$FIX/usr/bin:\
$FIX/usr/libexec:\
$FIX/curlinstalled/bin:\
$FIX/emptydir:\
$FIX/missingdir:\
$FIX/unreadable:\
$FIX/opt/homebrew/bin/:\
$FIX/opt/homebrew/bin"
}

teardown() {
    chmod -R +rwx "$FIX" 2>/dev/null || true
    rm -rf "$FIX" 2>/dev/null || true
    teardown_raccoon_env
}

_mkexec() {
    mkdir -p "${1%/*}"
    printf '#!/bin/sh\nexit 0\n' > "$1"
    chmod +x "$1"
}

_build_fixture() {
    # brew: bin is a relative symlink into Cellar (../Cellar/...). Attribution
    # only works if the ".." is folded away before the prefix match.
    _mkexec "$FIX/opt/homebrew/Cellar/rg/14.1.0/bin/rg"
    mkdir -p "$FIX/opt/homebrew/bin"
    ln -s "../Cellar/rg/14.1.0/bin/rg" "$FIX/opt/homebrew/bin/rg"

    # macports: plain executable, no symlink
    _mkexec "$FIX/opt/local/bin/wget"

    # nix: absolute symlink into /nix/store, plus a ~/.nix-profile entry
    _mkexec "$FIX/nix/store/abc-hello/bin/hello"
    mkdir -p "$FIX/nix-bin"
    ln -s "$FIX/nix/store/abc-hello/bin/hello" "$FIX/nix-bin/hello"
    _mkexec "$HOME/.nix-profile/bin/nix-shell"

    # go install / cargo / pipx
    _mkexec "$HOME/go/bin/gopls"
    _mkexec "$HOME/.cargo/bin/rg"
    _mkexec "$HOME/.local/bin/black"

    # mise shim — shadowing on purpose, must NOT read as an overlap
    _mkexec "$HOME/.local/share/mise/shims/python"
    # a tool mise installed, shadowed per project but not a shim file itself
    _mkexec "$HOME/.local/share/mise/installs/node/22.0.0/bin/node"
    # the mise binary itself, installed by brew: attributed to brew, not shim
    _mkexec "$FIX/opt/homebrew/Cellar/mise/2026.8.1/bin/mise"
    ln -s "../Cellar/mise/2026.8.1/bin/mise" "$FIX/opt/homebrew/bin/mise"

    # npm: relative symlink from <prefix>/bin into <prefix>/lib/node_modules
    _mkexec "$FIX/npm/lib/node_modules/typescript/bin/tsc"
    mkdir -p "$FIX/npm/bin"
    ln -s "../lib/node_modules/typescript/bin/tsc" "$FIX/npm/bin/tsc"

    # an Apple binary under SIP: attributed to system, not orphan
    _mkexec "$FIX/usr/bin/system-tool"
    _mkexec "$FIX/usr/libexec/libexec-tool"

    # dropped by a curl installer: no manager prefix matches these at all,
    # and these are the only rows that may come back as orphans
    _mkexec "$FIX/curlinstalled/bin/orphan"
    # JSON escaping: both characters are legal in a POSIX filename
    _mkexec "$FIX/curlinstalled/bin/back\\slash"
    _mkexec "$FIX/curlinstalled/bin/dq\"uote"
    ln -s "./nowhere" "$FIX/curlinstalled/bin/dead"
    ln -s "loopb" "$FIX/curlinstalled/bin/loopa"
    ln -s "loopa" "$FIX/curlinstalled/bin/loopb"

    # PATH entries that must be skipped in silence
    mkdir -p "$FIX/emptydir"
    mkdir -p "$FIX/unreadable"
    chmod 000 "$FIX/unreadable"
}

# Grep one JSON record by name (records are one per line).
_record() {
    printf '%s\n' "$output" | grep "\"name\": \"$1\"" || true
}

# ---------------------------------------------------------------- attribution

@test "overlap: brew relative symlink into Cellar resolves and attributes to brew" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    rec=$(_record rg | grep "opt/homebrew/bin/rg")
    [[ "$rec" == *"\"manager\": \"brew\""* ]]
    [[ "$rec" == *"Cellar/rg/14.1.0/bin/rg"* ]]
    # the ".." must be gone, not carried into the resolved path
    [[ "$rec" != *".."* ]]
}

@test "overlap: macports bin attributes to macports" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record wget)" == *"\"manager\": \"macports\""* ]]
}

@test "overlap: absolute symlink into nix store attributes to nix" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record hello)" == *"\"manager\": \"nix\""* ]]
}

@test "overlap: nix-profile entry attributes to nix" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record nix-shell)" == *"\"manager\": \"nix\""* ]]
}

@test "overlap: go bin attributes to go" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record gopls)" == *"\"manager\": \"go\""* ]]
}

@test "overlap: cargo bin attributes to cargo" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record rg | grep cargo)" == *"\"manager\": \"cargo\""* ]]
}

@test "overlap: local bin attributes to pipx" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record black)" == *"\"manager\": \"pipx\""* ]]
}

@test "overlap: npm relative symlink into node_modules attributes to npm" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    rec=$(_record tsc)
    [[ "$rec" == *"\"manager\": \"npm\""* ]]
    [[ "$rec" == *"node_modules/typescript/bin/tsc"* ]]
}

@test "overlap: unmatched path is an orphan" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record orphan)" == *"\"manager\": \"orphan\""* ]]
}

@test "overlap: JSON escapes backslashes and double quotes" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    assert_output_contains '"name": "back\\slash"'
    assert_output_contains '"name": "dq\"uote"'
}

@test "overlap: Apple binaries under SIP attribute to system" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record system-tool)" == *'"manager": "system"'* ]]
    [[ "$(_record libexec-tool)" == *'"manager": "system"'* ]]
}

@test "overlap: orphan is left for genuinely unattributed binaries only" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    orphans=$(printf '%s\n' "$output" | grep '"manager": "orphan"')
    # there are orphans, and every one of them comes from the curl-installed
    # tree — nothing from /usr, /bin or /sbin is allowed to land here
    [[ -n "$orphans" ]]
    stray=$(printf '%s\n' "$orphans" | grep -vcF "$FIX/curlinstalled/bin" || true)
    [[ "$stray" == "0" ]]
}

# ---------------------------------------------------------------------- shims

@test "overlap: mise shim is its own category, not an orphan" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    rec=$(_record python)
    [[ "$rec" == *"\"manager\": \"shim\""* ]]
    [[ "$rec" != *"orphan"* ]]
}

@test "overlap: a tool installed by mise reads as a shim" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record node)" == *'"manager": "shim"'* ]]
}

@test "overlap: the mise binary itself belongs to the manager that shipped it" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record mise)" == *'"manager": "brew"'* ]]
}

# --------------------------------------------------------- symlink resolution

@test "overlap: circular symlink terminates and is reported once" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$(_record loopa | wc -l | tr -d ' ')" == "1" ]]
    [[ "$(_record loopb | wc -l | tr -d ' ')" == "1" ]]
}

@test "overlap: broken symlink still appears in the map" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ -n "$(_record dead)" ]]
}

# --------------------------------------------------------------------- de-dup

@test "overlap: same basename in two managers stays two rows" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    # rg exists in both brew and cargo — collapsing them would destroy the
    # shadowing signal that phase 2 needs.
    [[ "$(_record rg | wc -l | tr -d ' ')" == "2" ]]
}

@test "overlap: duplicate PATH directory is walked once" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    # $FIX/opt/homebrew/bin appears three times in RCC_OVERLAP_PATH: plain,
    # with a trailing slash, and plain again
    [[ "$(_record rg | grep -c homebrew | tr -d ' ')" == "1" ]]
}

# ------------------------------------------------------------ skipped entries

@test "overlap: missing and unreadable PATH dirs are skipped without warning" {
    run bash -c "bash '$SCRIPT_DIR/bin/overlap.sh' --json 2>&1 >/dev/null"
    assert_success
    assert_output ""
}

@test "overlap: empty PATH dir produces no rows and no error" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    [[ "$output" != *"emptydir"* ]]
}

# ------------------------------------------------------------------ read-only

@test "overlap: writes nothing to the scanned tree" {
    before=$(find "$FIX" 2>/dev/null | sort)
    run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    after=$(find "$FIX" 2>/dev/null | sort)
    [[ "$before" == "$after" ]]
}

# ----------------------------------------------------------------- table + cli

@test "overlap: table output lists the executables" {
    run bash "$SCRIPT_DIR/bin/overlap.sh"
    assert_success
    assert_output_contains "gopls"
    assert_output_contains "brew"
}

@test "overlap: table rows all have the same width" {
    run bash "$SCRIPT_DIR/bin/overlap.sh"
    assert_success
    # long fixture paths must be trimmed, not allowed to blow the columns out
    distinct=$(printf '%s\n' "$output" | grep '^|' | awk '{ print length($0) }' | sort -u | wc -l | tr -d ' ')
    [[ "$distinct" == "1" ]]
}

@test "overlap: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --help
    assert_success
}

@test "overlap: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" -h
    assert_success
}

@test "overlap: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --help
    assert_output_contains "Usage"
}

@test "overlap: unknown flag fails" {
    run bash "$SCRIPT_DIR/bin/overlap.sh" --nonexistent
    assert_failure
}

@test "overlap: empty PATH yields an empty JSON array" {
    RCC_OVERLAP_PATH="" run bash "$SCRIPT_DIR/bin/overlap.sh" --json
    assert_success
    assert_output "[]"
}
