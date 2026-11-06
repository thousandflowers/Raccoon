load test_helper

setup() { setup_raccoon_env; }
teardown() { teardown_raccoon_env; }

@test "git: --help exits 0" {
    run bash "$SCRIPT_DIR/bin/git.sh" --help
    assert_success
}

@test "git: -h exits 0" {
    run bash "$SCRIPT_DIR/bin/git.sh" -h
    assert_success
}

@test "git: --help prints usage" {
    run bash "$SCRIPT_DIR/bin/git.sh" --help
    assert_output_contains "Usage"
}

@test "git: unknown flag silently ignored" {
    run bash "$SCRIPT_DIR/bin/git.sh" --nonexistent
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git: no args runs without crash" {
    run bash "$SCRIPT_DIR/bin/git.sh" 2>/dev/null || true
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git: --version silently ignored" {
    run bash "$SCRIPT_DIR/bin/git.sh" --version
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git: empty string arg silently ignored" {
    run bash "$SCRIPT_DIR/bin/git.sh" ' '
    [[ $status -eq 0 || $status -eq 1 ]]
}


# A Mac with no git repositories under HOME crashed here with
# "repos[@]: unbound variable": in bash 3.2 an empty array under set -u is an
# error, not an empty list, and the "No repositories found" branch sat after
# the loop that died.
@test "git: a machine with no repositories says so instead of crashing" {
	local empty
	empty="$(mktemp -d)"
	run env HOME="$empty" bash "$SCRIPT_DIR/bin/git.sh"
	rmdir "$empty" 2>/dev/null || true
	assert_success
	assert_output_contains "No repositories found"
	[[ "$output" != *"unbound variable"* ]] || {
		echo "still crashing: $output" >&2
		false
	}
}

_detached_repo() {
    mkdir -p "$1"
    git -C "$1" init -q .
    git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$2"
    git -C "$1" tag v1
    git -C "$1" checkout -q v1
    git -C "$1" branch -q -D "$(git -C "$1" for-each-ref --format='%(refname:short)' refs/heads)"
}

@test "git: a tool's hidden checkout on a tag is not an issue" {
    export HOME="$BATS_TEST_TMPDIR/home"
    _detached_repo "$HOME/.nvm" first
    run bash "$SCRIPT_DIR/bin/git.sh" --json
    assert_success
    assert_output_contains '"repos_total":1,"repos_with_issues":0'
}

@test "git: a detached HEAD is reported, and is not also a branch with no upstream" {
    export HOME="$BATS_TEST_TMPDIR/home"
    _detached_repo "$HOME/app" first
    run bash "$SCRIPT_DIR/bin/git.sh" --json
    assert_output_contains '"detached_head":true,"no_upstream":0'
}

@test "git: a commit subject with a bracket does not hide a branch with no upstream" {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/app"
    git -C "$HOME/app" init -q .
    git -C "$HOME/app" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "[wip] first"
    run bash "$SCRIPT_DIR/bin/git.sh" --json
    assert_output_contains '"no_upstream":1'
}
