#!/usr/bin/env bats
# Tests for client profiles (rcc audit --profile / --profile-save / -list / -delete).

load test_helper

setup() {
	setup_raccoon_env
}

teardown() {
	teardown_raccoon_env
}

@test "audit --profile creates the profile directory" {
	run bash "$SCRIPT_DIR/bin/audit.sh" --profile mario-bianchi
	assert_success
	[[ -d "$HOME/.raccoon/profiles/mario-bianchi" ]]
	assert_output_contains "Nuovo profilo 'mario-bianchi' creato"
}

@test "audit --profile-save then --profile-list shows the saved profile" {
	REPORT_CLIENT="Jane Doe" REPORT_SHOP="MacFix Pro" REPORT_TECH="Mario" \
		run bash "$SCRIPT_DIR/bin/audit.sh" --profile-save acme < /dev/null
	assert_success
	[[ -f "$HOME/.raccoon/profiles/acme/meta" ]]
	run bash "$SCRIPT_DIR/bin/audit.sh" --profile-list
	assert_success
	assert_output_contains "acme"
}

@test "audit --profile loads CLIENT from the profile meta into the report" {
	local dir="$HOME/.raccoon/profiles/withmeta"
	mkdir -p "$dir"
	printf 'CLIENT=%s\nSHOP=%s\nTECH=%s\nSAVED=x\n' "Acme Corp" "MacFix Pro" "Mario" > "$dir/meta"
	run bash "$SCRIPT_DIR/bin/audit.sh" --profile withmeta --md --report "$HOME/r.md"
	assert_success
	grep -q "Acme Corp" "$HOME/r.md"
}

@test "audit --profile appends the profile config to the skip list" {
	local dir="$HOME/.raccoon/profiles/withconfig"
	mkdir -p "$dir"
	printf 'Firewall\n' > "$dir/config"
	run bash -c "source '$SCRIPT_DIR/bin/audit.sh'; PROFILE_NAME=withconfig; PROFILES_DIR='$HOME/.raccoon/profiles'; load_profile; printf '%s' \"\$FIX_SKIP\""
	assert_success
	assert_output_contains "Firewall"
}

@test "audit --profile-delete declined keeps the directory" {
	mkdir -p "$HOME/.raccoon/profiles/keepme"
	run bash "$SCRIPT_DIR/bin/audit.sh" --profile-delete keepme <<< "n"
	assert_success
	[[ -d "$HOME/.raccoon/profiles/keepme" ]]
}

@test "audit --profile-delete confirmed removes the directory" {
	mkdir -p "$HOME/.raccoon/profiles/dropme"
	run bash "$SCRIPT_DIR/bin/audit.sh" --profile-delete dropme <<< "y"
	assert_success
	[[ ! -d "$HOME/.raccoon/profiles/dropme" ]]
}
