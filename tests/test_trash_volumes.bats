load test_helper
setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "trash --json: the home trash is still the top-level answer" {
    run bash "$SCRIPT_DIR/bin/trash.sh" --json
    assert_success
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["path"].endswith("/.Trash"), d["path"]
assert isinstance(d["count"], int), d
assert isinstance(d["volumes"], list), d
'
}

@test "trash --json: a volume trash is found when one exists" {
    # macOS puts an external volume's deleted files in /Volumes/<v>/.Trashes/<uid>,
    # never in ~/.Trash. Reading only the home one reports an empty trash while
    # the drive holds gigabytes.
    local uid; uid=$(id -u)
    local root="$BATS_TEST_TMPDIR/Volumes"
    mkdir -p "$root/rcc-test-vol/.Trashes/$uid"
    printf 'deleted' > "$root/rcc-test-vol/.Trashes/$uid/file.txt"
    RCC_VOLUMES_ROOT="$root" run bash "$SCRIPT_DIR/bin/trash.sh" --json
    assert_success
    assert_output_contains "rcc-test-vol"
    printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert len(d["volumes"]) == 1, d["volumes"]
assert d["volumes"][0]["count"] == 1, d["volumes"]
'

}

@test "trash --json: a quote in a volume name cannot break the document" {
    printf '%s' "$(bash "$SCRIPT_DIR/bin/trash.sh" --json)" | python3 -c 'import json,sys; json.load(sys.stdin)'
}
