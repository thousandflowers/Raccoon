load test_helper

setup() {
	setup_raccoon_env
}

teardown() {
	teardown_raccoon_env
}

# --- regression: the two unsafe auto-fixes must stay gone ---

@test "checks.sh: never auto-sets a public DNS resolver" {
	! grep -q "setdnsservers Wi-Fi 8.8.8.8" "$SCRIPT_DIR/lib/audit/checks.sh"
}

@test "checks.sh: never recursively strips the quarantine flag" {
	! grep -q "xattr -r -d com.apple.quarantine" "$SCRIPT_DIR/lib/audit/checks.sh"
}

# --- regression: destructive fixes back up first ---

@test "checks.sh: authorized_keys / cron / launchagents / login-items snapshot before deleting" {
	# Every line that deletes user data must also call _fix_backup_dir.
	local destructive
	destructive="$(grep -nE 'rm .*authorized_keys|crontab -r|rm -f ~/Library/LaunchAgents|delete every login item' "$SCRIPT_DIR/lib/audit/checks.sh")"
	[[ -n "$destructive" ]]
	while IFS= read -r line; do
		[[ "$line" == *"_fix_backup_dir"* ]]
	done <<<"$destructive"
}

# --- per-machine opt-out ---

@test "load_fix_skips: reads check names, ignores comments and blanks" {
	source "$SCRIPT_DIR/bin/audit.sh"
	printf '# comment\nCron Jobs\n\n  Authorized Keys  \n' > "$HOME/.raccoon/audit.conf"
	load_fix_skips
	_fix_skipped "Cron Jobs"
	! _fix_skipped "Login Items"
	! _fix_skipped "# comment"
}

@test "fix_issue: a skipped check is never queued" {
	source "$SCRIPT_DIR/bin/audit.sh"
	printf 'Cron Jobs\n' > "$HOME/.raccoon/audit.conf"
	load_fix_skips
	AUTO_FIX=false
	FIX_QUEUE=()
	fix_issue "Cron Jobs" "echo nope"     # opted out -> dropped
	fix_issue "Login Items" "echo queued" # not opted out -> queued
	[[ "${#FIX_QUEUE[@]}" -eq 1 ]]
	[[ "${FIX_QUEUE[0]}" == "Login Items|echo queued" ]]
}

@test "fix_issue: no audit.conf means nothing is skipped" {
	source "$SCRIPT_DIR/bin/audit.sh"
	load_fix_skips
	! _fix_skipped "Cron Jobs"
}

# --- backup dir helper ---

@test "_fix_backup_dir: creates a timestamped dir under ~/.raccoon/fix-backups" {
	source "$SCRIPT_DIR/bin/audit.sh"
	local dir
	dir="$(_fix_backup_dir)"
	[[ -d "$dir" ]]
	[[ "$dir" == "$HOME/.raccoon/fix-backups/"* ]]
}

# --- regression: a non-interactive audit must not stop to ask ----------------
#
# `rcc audit` used to end by asking "Fix N issue(s) automatically? [y/N]" and
# reading stdin with nothing checking whether anyone could answer. Under cron or
# CI, where stdin never closes, it waited forever — and `--dry-run` reaching the
# same prompt stopped to ask permission to act, which is the one thing that flag
# promises not to do. Eleven minutes on a single test is how it was found.
#
# `run` gives these tests a stdin that is not a terminal, which is the case that
# used to hang.

@test "audit: a non-interactive run never asks the fix question" {
	run bash "$SCRIPT_DIR/bin/audit.sh"
	assert_audit_exit
	[[ "$output" != *"automatically? [y/N]"* ]]
}

@test "audit: --dry-run never asks either" {
	run bash "$SCRIPT_DIR/bin/audit.sh" --dry-run
	assert_audit_exit
	[[ "$output" != *"automatically? [y/N]"* ]]
}

@test "audit: a non-interactive run still says how many fixes are available" {
	# The count is information: someone running this from a script loses the
	# question, not the answer to "is there anything to fix here". Skipped on a
	# machine with nothing to fix, which is the other half of the same rule.
	run bash "$SCRIPT_DIR/bin/audit.sh"
	assert_audit_exit
	[[ "$output" == *"can be fixed automatically"* ]] || skip "nothing fixable on this machine"
	assert_output_contains "Run: rcc audit --fix"
}

@test "audit: a non-interactive run fixes nothing" {
	run bash "$SCRIPT_DIR/bin/audit.sh"
	assert_audit_exit
	# The lines the apply path prints. None may appear without --fix.
	[[ "$output" != *"Applying fixes"* ]]
	[[ "$output" != *"→ Fix "* ]]
	[[ "$output" != *"Fixed:"* ]]
}
