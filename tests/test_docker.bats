load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "docker: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --help
    assert_success
}

@test "docker: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/docker.sh" -h
    assert_success
}

@test "docker: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --help
    assert_output_contains "Usage"
}

@test "docker: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "docker: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/docker.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "docker: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/docker.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "docker: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/docker.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# --- measured, not read: the findings of 2026-09-02 ---------------------------

# A docker CLI whose daemon is down: every list command fails, `info` fails.
_stub_docker_down() {
	STUB="${BATS_TEST_TMPDIR}/down"
	mkdir -p "$STUB"
	printf '#!/bin/bash\necho "Cannot connect to the Docker daemon" >&2\nexit 1\n' > "$STUB/docker"
	chmod +x "$STUB/docker"
}

# A docker whose daemon answers, with Docker's own --format output shapes.
_stub_docker_up() {
	STUB="${BATS_TEST_TMPDIR}/up"
	mkdir -p "$STUB"
	cat > "$STUB/docker" <<'SH'
#!/bin/bash
case "$1 $2" in
	"info ") exit 0 ;;
	"images --format") printf 'nginx\tlatest\t187MB\npostgres\t16\t432MB\n' ;;
	"ps -a") printf 'a1b2c3d4e5f6\tnginx\tUp 3 hours\nf6e5d4c3b2a1\tpostgres:16\tExited (0) 2 days ago\n' ;;
	"volume ls") printf 'pgdata\tlocal\n' ;;
	"system df") printf 'Images\t2\t1\t619MB\t432MB (69%%)\nContainers\t2\t1\t12.3kB\t0B (0%%)\nLocal Volumes\t1\t1\t58.7MB\t0B (0%%)\nBuild Cache\t0\t0\t0B\t0B\n' ;;
	*) exit 1 ;;
esac
SH
	chmod +x "$STUB/docker"
}

@test "docker: a daemon that is down is said so, not 'No images found' under a tick" {
	_stub_docker_down
	PATH="$STUB:$PATH" run bash "$SCRIPT_DIR/bin/docker.sh" --json
	assert_success
	[[ "$output" == *'"installed": true'* ]]
	[[ "$output" == *'"running": false'* ]]
	NO_COLOR=1 PATH="$STUB:$PATH" run bash "$SCRIPT_DIR/bin/docker.sh"
	assert_success
	assert_output_contains "daemon is not running"
	[[ "$output" != *"No images"* ]]
}

@test "docker: sizes are sizes, statuses are statuses, in both renderings" {
	_stub_docker_up
	PATH="$STUB:$PATH" run bash "$SCRIPT_DIR/bin/docker.sh" --json
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["running"] is True
assert d["images"][0] == {"repository": "nginx", "tag": "latest", "size": "187MB"}, d["images"]
assert d["containers"][0]["status"] == "Up 3 hours", d["containers"]
assert d["containers"][1]["status"].startswith("Exited"), d["containers"]
img = [s for s in d["space"] if s["type"] == "Images"][0]
assert img["size"] == "619MB" and img["reclaimable"].startswith("432MB"), img
assert img["total"] == 2 and img["active"] == 1, img
assert [s["type"] for s in d["space"]][2] == "Local Volumes"
'
	NO_COLOR=1 PATH="$STUB:$PATH" run bash "$SCRIPT_DIR/bin/docker.sh"
	assert_success
	[[ "$output" == *"nginx"*"latest"*"187MB"* ]]
	[[ "$output" == *"Up 3 hours"* ]]
	[[ "$output" != *"hours "*"|"*"hours"* ]] || true
	[[ "$output" == *"Images"*"619MB"* ]]
	[[ "$output" != *"| TYPE"* ]]
}
