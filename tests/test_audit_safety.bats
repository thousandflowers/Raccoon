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
