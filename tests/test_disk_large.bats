#!/usr/bin/env bats
# Tests for `rcc disk --large`.

load test_helper

setup() {
	setup_raccoon_env
}

teardown() {
	teardown_raccoon_env
}

@test "disk --large on a small path exits 0" {
	run bash "$SCRIPT_DIR/bin/disk.sh" --large /tmp --top 3
	assert_success
}

@test "disk --large --top 0 exits 0" {
	run bash "$SCRIPT_DIR/bin/disk.sh" --large /tmp --top 0
	assert_success
}

@test "disk --help mentions --large" {
	run bash "$SCRIPT_DIR/bin/disk.sh" --help
	assert_success
	assert_output_contains "--large"
}
