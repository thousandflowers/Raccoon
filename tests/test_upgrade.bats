load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "upgrade: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --help
    assert_success
}

@test "upgrade: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" -h
    assert_success
}

@test "upgrade: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --help
    assert_output_contains "Usage"
}

@test "upgrade: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "upgrade: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "upgrade: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "upgrade: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "upgrade: --parallel is accepted" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --parallel --dry-run
    assert_success
}

@test "upgrade: --serial is accepted" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --serial --dry-run
    assert_success
}

@test "upgrade: help documents both parallel and serial" {
    run bash "$SCRIPT_DIR/bin/upgrade.sh" --help
    assert_success
    [[ "$output" == *"--parallel"* ]]
    [[ "$output" == *"--serial"* ]]
}

# These assert on the marker the parallel path prints, not on an internal
# variable: sourcing the script to read one is not possible, since --help exits.
#
# The user picked serial-by-default: this path installs software, so the newer
# concurrent code must never run unless it was actually asked for.
@test "upgrade: defaults to serial when nothing is set" {
    run env -u RCC_PARALLEL bash "$SCRIPT_DIR/bin/upgrade.sh" --dry-run
    assert_success
    [[ "$output" != *"upgrades in parallel"* ]]
}

@test "upgrade: RCC_PARALLEL=1 turns parallel on" {
    run env RCC_PARALLEL=1 bash "$SCRIPT_DIR/bin/upgrade.sh" --dry-run
    assert_success
    [[ "$output" == *"upgrades in parallel"* ]]
}

# --serial must win over the environment, or the escape hatch is useless.
@test "upgrade: --serial overrides RCC_PARALLEL=1" {
    run env RCC_PARALLEL=1 bash "$SCRIPT_DIR/bin/upgrade.sh" --serial --dry-run
    assert_success
    [[ "$output" != *"upgrades in parallel"* ]]
}

# Both branches must drive the same tool list, or adding a tool to one silently
# skips it in the other.
@test "upgrade: serial and parallel share one job list" {
    run grep -c "^\t\tupgrade_" "$SCRIPT_DIR/bin/upgrade.sh"
    assert_success
    [[ "$output" -eq 12 ]]
}

# A failing tool used to be swallowed by `|| true`, so the command exited 0 no
# matter what broke. Every upgrade pipeline must route its failure somewhere
# that gets reported.
@test "upgrade: tool failures are recorded, not swallowed" {
    run grep -cE "\|\| _note_failure " "$SCRIPT_DIR/bin/upgrade.sh"
    assert_success
    [[ "$output" -ge 15 ]]
}

# `npm outdated` exits 1 whenever it finds anything to update, so treating its
# status as a failure would cry wolf on every single run.
@test "upgrade: npm outdated is not treated as a failure" {
    run grep -n "npm outdated" "$SCRIPT_DIR/bin/upgrade.sh"
    assert_success
    [[ "$output" != *"_note_failure"* ]]
}

# Casks belong to `rcc apps`. A bare `brew upgrade` / `brew outdated` covers
# casks too, so every brew call here must be scoped with --formula.
@test "upgrade: never touches casks (brew calls scoped to --formula)" {
    run grep -nE '(^|[^-])brew (upgrade|outdated)' "$SCRIPT_DIR/bin/upgrade.sh"
    assert_success
    while IFS= read -r line; do
        [[ "$line" == *"--formula"* ]] || {
            echo "unscoped brew call (would upgrade casks): $line"
            return 1
        }
    done <<< "$output"
}

