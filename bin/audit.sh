#!/bin/bash

set -uo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

PASS_count=0
WARN_count=0
FAIL_count=0
declare -a FIX_QUEUE=()

# Global progress bar support
ACCUMULATED_RESULTS=()
ACCUMULATED_CATEGORIES=()
AUDIT_SILENT_MODE=false
CURRENT_CATEGORY=""

show_audit_help() {
	echo "Usage: rcc audit [options]"
	echo ""
	echo "Security audit: Comprehensive system security analysis"
	echo ""
	echo "Options:"
	echo "  --deep         Enable deep scan (full security audit, requires sudo)"
	echo "  --fix          Attempt to fix issues automatically"
	echo "  --fix --dry-run Show fixes without applying"
	echo "  --fix --force Apply fixes without confirmation"
	echo "  --quiet       Suppress non-essential output"
	echo "  --report FILE  Save report to file"
	echo "  --html        Output in HTML format"
	echo "  --csv         Output in CSV format"
	echo "  --json        Output in JSON format"
	echo "  --history     Show previous audit runs"
	echo "  --diff        Compare with previous run"
	echo "  --watch       Schedule weekly auto-audit"
	echo "  --alert       Alert on new issues"
	echo "  --notify      Send notification on issues"
	echo "  --help, -h    Show this help"
}

DEEP_SCAN=false
AUTO_FIX=false
FIX_DRY_RUN=false
FIX_FORCE=false
QUIET_MODE=false
REPORT_FILE=""
OUTPUT_FORMAT="text"
SHOW_HISTORY=false
SHOW_DIFF=false
SCHEDULE_WEEKLY=false
ALERT_ON_ISSUES=false
NOTIFY=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--help | -h)
		show_audit_help
		exit 0
		;;
	--deep)
		DEEP_SCAN=true
		shift
		;;
	--fix)
		AUTO_FIX=true
		shift
		;;
	--dry-run)
		FIX_DRY_RUN=true
		shift
		;;
	--force)
		FIX_FORCE=true
		shift
		;;
	--quiet | -q)
		QUIET_MODE=true
		DEEP_SCAN=true
		shift
		;;
	--report)
		REPORT_FILE="$2"
		shift 2
		;;
	--report=*)
		REPORT_FILE="${1#--report=}"
		shift
		;;
	--html)
		OUTPUT_FORMAT="html"
		shift
		;;
	--csv)
		OUTPUT_FORMAT="csv"
		shift
		;;
	--json)
		OUTPUT_FORMAT="json"
		shift
		;;
	--history)
		SHOW_HISTORY=true
		shift
		;;
	--diff)
		SHOW_DIFF=true
		shift
		;;
	--watch)
		SCHEDULE_WEEKLY=true
		shift
		;;
	--alert)
		ALERT_ON_ISSUES=true
		shift
		;;
	--notify)
		NOTIFY=true
		shift
		;;
	*)
		shift
		;;
	esac
done

HISTORY_DIR="$HOME/.raccoon/audit-history"
[[ -d "$HISTORY_DIR" ]] || mkdir -p "$HISTORY_DIR"

print_result() {
	local status="$1"
	local label="$2"
	local icon=""
	local colored_label=""
	
	if [[ "$status" == "pass" ]]; then
		((PASS_count++)) || true
	elif [[ "$status" == "warn" ]]; then
		((WARN_count++)) || true
	elif [[ "$status" == "fail" ]]; then
		((FAIL_count++)) || true
	fi
	
	if [[ "$AUDIT_SILENT_MODE" == "true" ]]; then
		ACCUMULATED_RESULTS+=("$status:$CURRENT_CATEGORY:$label")
		return
	fi
	
	if [[ "$status" == "pass" ]]; then
		icon="${GREEN}✓${NC}"
		colored_label="${GREEN}$label${NC}"
	elif [[ "$status" == "warn" ]]; then
		icon="${YELLOW}⚠${NC}"
		colored_label="${YELLOW}$label${NC}"
	elif [[ "$status" == "fail" ]]; then
		icon="${RED}✗${NC}"
		colored_label="${RED}$label${NC}"
	else
		icon="${GRAY}○${NC}"
		colored_label="${GRAY}$label${NC}"
	fi
	
	local raw_len=${#label}
	local pad_len=$((34 - raw_len))
	local padding
	padding=$(printf '%*s' "$pad_len")
	
	printf "│ %s %s%s%s │\n" "$icon" "$colored_label" "$padding"
}

echo_result() {
	local status="$1"
	local result="$2"
	print_result "$status" "$result"
}

print_category() {
	local name="$1"
	shift
	local -a items=("$@")
	
	if [[ "$AUDIT_SILENT_MODE" == "true" ]]; then
		CURRENT_CATEGORY="$name"
		ACCUMULATED_CATEGORIES+=("$name")
		for item in "${items[@]}"; do
			local status="$(echo "$item" | cut -d: -f1)"
			local rest="$(echo "$item" | cut -d: -f2-)"
			print_result "$status" "$rest"
		done
		return
	fi
	
	local name_len=${#name}
	local padding=$((37 - name_len))
	local pad_str
	pad_str=$(printf '%*s' "$padding" '')
	
	echo ""
	echo "+---------------------------------------+"
	echo "| ${CYAN}${name}${NC}${pad_str}|"
	echo "+---------------------------------------+"

	for item in "${items[@]}"; do
		local status="$(echo "$item" | cut -d: -f1)"
		local rest="$(echo "$item" | cut -d: -f2-)"
		echo_result "$status" "$rest"
	done
	
	echo "+---------------------------------------+"
}

print_summary() {
	echo ""
	echo "+---------------------------------------+"
	echo "| ${PURPLE_BOLD}Summary${NC}                           |"
	echo "+---------------------------------------+"
	printf "| ${GREEN}Pass${NC}    | %5s                     |\n" "$PASS_count"
	printf "| ${YELLOW}Warning${NC} | %5s                     |\n" "$WARN_count"
	printf "| ${RED}Fail${NC}   | %5s                     |\n" "$FAIL_count"
	echo "+---------------------------------------+"

	if [[ $FAIL_count -eq 0 && $WARN_count -eq 0 ]]; then
		echo "| ${GREEN}✓ All checks passed${NC}              |"
	elif [[ $FAIL_count -eq 0 ]]; then
		echo "| ${YELLOW}⚠ No critical issues${NC}           |"
	else
		echo "| ${RED}✗ Action required${NC}                |"
	fi

	echo "+---------------------------------------+"
}

save_to_history() {
	local timestamp
	timestamp="$(date +%Y-%m-%d_%H:%M:%S)"
	local history_file="$HISTORY_DIR/audit_${timestamp}.json"
	
	cat > "$history_file" << EOF
{
  "timestamp": "$timestamp",
  "pass": $PASS_count,
  "warning": $WARN_count,
  "fail": $FAIL_count,
  "deep": $DEEP_SCAN,
  "results": []
}
EOF

	local latest_link="$HISTORY_DIR/latest.json"
	ln -sf "$history_file" "$latest_link" 2>/dev/null || true
}

show_audit_history() {
	echo "${PURPLE_BOLD}-- Audit History--${NC}"
	echo ""
	
	if [[ ! -d "$HISTORY_DIR" ]]; then
		echo "  No history found"
		return
	fi
	
	local -a history_files
	history_files=($(ls -t "$HISTORY_DIR"/audit_*.json 2>/dev/null | head -10))
	
	if [[ ${#history_files[@]} -eq 0 ]]; then
		echo "  No history found"
		return
	fi
	
	for file in "${history_files[@]}"; do
		local date
		date="$(basename "$file" | sed 's/audit_//' | sed 's/.json//' | sed 's/_/ /')"
		local pass=""; local warn=""; local fail=""
		
		pass="$(grep -o '"pass": [0-9]*' "$file" | grep -o '[0-9]*' || echo "0")"
		warn="$(grep -o '"warning": [0-9]*' "$file" | grep -o '[0-9]*' || echo "0")"
		fail="$(grep -o '"fail": [0-9]*' "$file" | grep -o '[0-9]*' || echo "0")"
		
		echo "  $date"
		echo "    ${GREEN}Pass: $pass${NC} ${YELLOW}Warn: $warn${NC} ${RED}Fail: $fail${NC}"
		echo ""
	done
	
	echo "  Run 'rcc audit --deep --diff' to compare with previous"
}

show_diff() {
	echo "${PURPLE_BOLD}-- Diff with Previous Run--${NC}"
	echo ""
	
	local latest_link="$HISTORY_DIR/latest.json"
	if [[ ! -L "$latest_link" ]]; then
		echo "  No previous run found"
		return
	fi
	
	local prev_file
	prev_file="$(readlink "$latest_link")"
	
	local curr_pass="$PASS_count"
	local curr_warn="$WARN_count"
	local curr_fail="$FAIL_count"
	
	local prev_pass=0; local prev_warn=0; local prev_fail=0
	prev_pass="$(grep -o '"pass": [0-9]*' "$prev_file" | grep -o '[0-9]*' | head -1)"
	prev_warn="$(grep -o '"warning": [0-9]*' "$prev_file" | grep -o '[0-9]*' | head -1)"
	prev_fail="$(grep -o '"fail": [0-9]*' "$prev_file" | grep -o '[0-9]*' | head -1)"
	
	echo "  Previous: ${GREEN}Pass: $prev_pass${NC} ${YELLOW}Warn: $prev_warn${NC} ${RED}Fail: $prev_fail${NC}"
	echo "  Current:  ${GREEN}Pass: $curr_pass${NC} ${YELLOW}Warn: $curr_warn${NC} ${RED}Fail: $curr_fail${NC}"
	echo ""
	
	local pass_diff=$((curr_pass - prev_pass))
	local warn_diff=$((curr_warn - prev_warn))
	local fail_diff=$((curr_fail - prev_fail))
	
	if [[ $pass_diff -gt 0 ]]; then
		echo "  ${GREEN}↑ $pass_diff more checks passed${NC}"
	elif [[ $pass_diff -lt 0 ]]; then
		echo "  ${RED}↓ $((-pass_diff)) fewer checks passed${NC}"
	fi
	
	if [[ $warn_diff -gt 0 ]]; then
		echo "  ${YELLOW}↑ $warn_diff more warnings${NC}"
	elif [[ $warn_diff -lt 0 ]]; then
		echo "  ${GREEN}↓ $((-warn_diff)) fewer warnings${NC}"
	fi
	
	if [[ $fail_diff -gt 0 ]]; then
		echo "  ${RED}↑ $fail_diff more failures${NC}"
	elif [[ $fail_diff -lt 0 ]]; then
		echo "  ${GREEN}↓ $((-fail_diff)) fewer failures${NC}"
	fi
}

schedule_weekly() {
	local plist_file="$HOME/Library/LaunchAgents/com.raccoon.audit.plist"
	local audit_path
	audit_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/audit.sh"
	
	cat > "$plist_file" << EOFPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.raccoon.audit</string>
	<key>ProgramArguments</key>
	<array>
		<string>${audit_path}</string>
		<string>--deep</string>
		<string>--json</string>
		<string>--alert</string>
	</array>
	<key>RunAtLoad</key>
	<false/>
	<key>StartCalendarInterval</key>
	<array>
		<dict>
			<key>Weekday</key>
			<integer>0</integer>
			<key>Hour</key>
			<integer>9</integer>
			<key>Minute</key>
			<integer>0</integer>
		</dict>
	</array>
</dict>
</plist>
EOFPLIST

	launchctl load "$plist_file" 2>/dev/null || true
	echo "  Weekly audit scheduled (Sundays at 9:00 AM)"
}

send_notification() {
	if [[ $FAIL_count -gt 0 || $WARN_count -gt 0 ]]; then
		local title="Security Audit: Issues Found"
		local body="$FAIL_count failures, $WARN_count warnings"
		
		osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null || true
	fi
}

print_output_html() {
	local pass_pct=0
	local total=$((PASS_count + WARN_count + FAIL_count))
	[[ $total -gt 0 ]] && pass_pct=$((PASS_count * 100 / total))
	
	cat << EOFHTML
<!DOCTYPE html>
<html>
<head>
	<meta charset="UTF-8">
	<title>Security Audit Report</title>
	<style>
		body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; }
		h1 { color: #1d1d1f; border-bottom: 2px solid #0066cc; padding-bottom: 10px; }
		.summary { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; }
		.pass { color: #28a745; }
		.warn { color: #ffc107; }
		.fail { color: #dc3545; }
	</style>
</head>
<body>
	<h1>Security Audit Report</h1>
	<p>Generated: $(date)</p>
	<div class="summary">
		<h2>Summary</h2>
		<p class="pass">Pass: $PASS_count ($pass_pct%)</p>
		<p class="warn">Warning: $WARN_count</p>
		<p class="fail">Fail: $FAIL_count</p>
	</div>
</body>
</html>
EOFHTML
}

print_output_csv() {
	echo "Status,Category,Check,Result"
	echo "pass,Summary,$PASS_count passed"
	echo "warn,Summary,$WARN_count warnings"
	echo "fail,Summary,$FAIL_count failures"
}

print_output_json() {
	echo "{"
	echo "  \"timestamp\": \"$(date -Iseconds)\","
	echo "  \"audit_type\": \"$([ "$DEEP_SCAN" == "true" ] && echo "deep" || echo "basic")\","
	echo "  \"pass\": $PASS_count,"
	echo "  \"warning\": $WARN_count,"
	echo "  \"fail\": $FAIL_count"
	echo "}"
}

fix_issue() {
	local check_name="$1"
	local fix_cmd="$2"

	if [[ "$AUTO_FIX" == "true" ]]; then
		if [[ "$FIX_DRY_RUN" == "true" ]]; then
			echo "  ${CYAN}→ Would fix: $check_name${NC}"
			echo "    Command: $fix_cmd"
			return
		fi

		if [[ "$FIX_FORCE" != "true" ]]; then
			echo -n "  ${YELLOW}→ Fix $check_name? [y/N] ${NC}"
			read -r -n 1 -t 5 answer || answer="n"
			echo ""
			[[ "$answer" != "y" && "$answer" != "Y" ]] && return
		fi

		echo "  ${YELLOW}→ Fixing: $check_name${NC}"
		eval "$fix_cmd" 2>/dev/null && echo "  ${GREEN}✓ Fixed${NC}" || echo "  ${RED}✗ Fix failed${NC}"
	else
		FIX_QUEUE+=("${check_name}|${fix_cmd}")
	fi
}

run_core_checks() {
	local -a core_results=()
	
	update_global_progress_info "audit: FileVault..."
	local fv_status
	fv_status="$(sudo fdesetup status 2>/dev/null | grep -i "filevault is" | head -1)"
	if echo "$fv_status" | grep -qi "enabled"; then
		core_results+=("pass:FileVault: Enabled")
	elif echo "$fv_status" | grep -qi "disabled"; then
		core_results+=("fail:FileVault: Disabled")
		fix_issue "FileVault" "sudo fdesetup enable -user \\$(whoami)"
	else
		core_results+=("warn:FileVault: Unknown")
	fi
	increment_global_progress
	
	update_global_progress_info "audit: SIP..."
	local sip_status
	sip_status="$(sudo csrutil status 2>/dev/null)"
	if echo "$sip_status" | grep -qi "enabled"; then
		core_results+=("pass:SIP: Enabled")
	elif echo "$sip_status" | grep -qi "disabled"; then
		core_results+=("fail:SIP: Disabled")
	else
		core_results+=("warn:SIP: Unknown")
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Gatekeeper..."
	local gk_status
	gk_status="$(spctl --status 2>/dev/null)"
	if echo "$gk_status" | grep -qi "enabled"; then
		core_results+=("pass:Gatekeeper: Enabled")
	else
		core_results+=("fail:Gatekeeper: Disabled")
		fix_issue "Gatekeeper" "sudo spctl --master-enable"
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Firewall..."
	local fw_status
	fw_status="$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)"
	if echo "$fw_status" | grep -qi "enabled"; then
		core_results+=("pass:Firewall: Enabled")
	else
		core_results+=("fail:Firewall: Disabled")
		fix_issue "Firewall" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --enable"
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Stealth Mode..."
	local stealth_status
	stealth_status="$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null)"
	if echo "$stealth_status" | grep -qi "enabled"; then
		core_results+=("pass:Stealth Mode: Enabled")
	else
		core_results+=("warn:Stealth Mode: Disabled")
		fix_issue "Stealth Mode" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Software Updates..."
	local updates
	updates="$(softwareupdate -l 2>/dev/null | grep -c "Recommended Update" 2>/dev/null)"
	[[ -z "$updates" ]] && updates="0"
	if [[ "$updates" -eq 0 ]]; then
		core_results+=("pass:Software Updates: Up to date")
	else
		core_results+=("warn:Software Updates: ${updates} pending")
	fi
	increment_global_progress
	
	print_category "Core Security" "${core_results[@]}"
}

run_network_checks() {
	local -a network_results=()
	
	update_global_progress_info "audit: Open Ports..."
	port_count="$(sudo lsof -i -P -n 2>/dev/null | grep LISTEN | wc -l 2>/dev/null)"
	[[ -z "$port_count" ]] && port_count="0"
	port_count="$(echo "$port_count" | sed 's/ *//g')"
	if [[ "$port_count" -lt 10 ]]; then
		network_results+=("pass:Open Ports: ${port_count} listening")
	else
		network_results+=("warn:Open Ports: ${port_count} listening")
		fix_issue "Open Ports" "echo 'Consider reviewing open ports with: sudo lsof -i -P -n'"
	fi
	increment_global_progress

	update_global_progress_info "audit: DNS Servers..."
	local dns_servers
	dns_servers="$(scutil --dns 2>/dev/null | grep "nameserver" | head -1 | awk '{print $NF}')"
	if [[ -n "$dns_servers" ]]; then
		network_results+=("pass:DNS Servers: ${dns_servers}")
	else
		network_results+=("warn:DNS Servers: None configured")
		fix_issue "DNS Servers" "networksetup -setdnsservers Wi-Fi 8.8.8.8"
	fi
	increment_global_progress

	update_global_progress_info "audit: VPN..."
	local vpn_count
	vpn_count="$(networksetup -listallnetworkservices 2>/dev/null | grep -c "VPN" 2>/dev/null)"
	[[ -z "$vpn_count" ]] && vpn_count="0"
	if [[ "$vpn_count" -eq 0 ]]; then
		network_results+=("pass:VPN: None configured")
	else
		network_results+=("warn:VPN: ${vpn_count} configured")
		fix_issue "VPN" "for svc in \$(networksetup -listallnetworkservices | grep VPN); do networksetup -disconnectvpn \"\$svc\" 2>/dev/null; done"
	fi
	increment_global_progress

	update_global_progress_info "audit: Bluetooth..."
	local bt_status
	bt_status="$(blueutil status 2>/dev/null)"
	if echo "$bt_status" | grep -qi "off"; then
		network_results+=("pass:Bluetooth: Off")
	elif echo "$bt_status" | grep -qi "powered on"; then
		if echo "$bt_status" | grep -qi "discoverable"; then
			network_results+=("fail:Bluetooth: On & discoverable")
		else
			network_results+=("pass:Bluetooth: On")
		fi
		fix_issue "Bluetooth" "sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0 && sudo killall -HUP blued 2>/dev/null || true"
	else
		network_results+=("warn:Bluetooth: Unknown")
		fix_issue "Bluetooth" "sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0 && sudo killall -HUP blued 2>/dev/null || true"
	fi
	increment_global_progress

	update_global_progress_info "audit: Sharing..."
	local sharing_count
	sharing_count="$(sharing -l 2>/dev/null | grep -c "Share" 2>/dev/null)"
	[[ -z "$sharing_count" ]] && sharing_count="0"
	if [[ "$sharing_count" -eq 0 ]]; then
		network_results+=("pass:Sharing: None enabled")
	else
		network_results+=("warn:Sharing: ${sharing_count} enabled")
		fix_issue "Sharing" "sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null; sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null; sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist 2>/dev/null; true"
	fi
	increment_global_progress

	update_global_progress_info "audit: SSH Daemon..."
	local sshd_check
	sshd_check="$(sudo launchctl list com.openssh.sshd 2>/dev/null)"
	if [[ -z "$sshd_check" ]] || echo "$sshd_check" | grep -q "not found"; then
		network_results+=("pass:SSH Daemon: Disabled")
	else
		network_results+=("warn:SSH Daemon: Running")
		fix_issue "SSH Daemon" "sudo launchctl unload /System/Library/LaunchDaemons/sshd.plist"
	fi
	increment_global_progress
	
	print_category "Network" "${network_results[@]}"
}

run_auth_checks() {
	local -a auth_results=()
	
	update_global_progress_info "audit: Auto-Login..."
	local auto_user
	auto_user="$(sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null)"
	if [[ -z "$auto_user" ]]; then
		auth_results+=("pass:Auto-Login: Disabled")
	else
		auth_results+=("fail:Auto-Login: User ${auto_user}")
		fix_issue "Auto-Login" "sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser"
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Keychain..."
	local keychains
	keychains="$(security list-keychains 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$keychains" ]] && keychains="0"
	keychains="$(echo "$keychains" | sed 's/ *//g')"
	if [[ "$keychains" -gt 0 ]]; then
		auth_results+=("pass:Keychain: ${keychains} available")
	else
		auth_results+=("warn:Keychain: None found")
	fi
	increment_global_progress
	
	update_global_progress_info "audit: SSH Keys..."
	local ssh_key_count
	ssh_key_count="$(ls -la ~/.ssh/*.pub 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$ssh_key_count" ]] && ssh_key_count="0"
	ssh_key_count="$(echo "$ssh_key_count" | sed 's/ *//g')"
	if [[ "$ssh_key_count" -eq 0 ]]; then
		auth_results+=("pass:SSH Keys: None")
	else
		auth_results+=("pass:SSH Keys: ${ssh_key_count} key(s)")
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Authorized Keys..."
	local auth_keys_count
	auth_keys_count="$(cat ~/.ssh/authorized_keys 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$auth_keys_count" ]] && auth_keys_count="0"
	auth_keys_count="$(echo "$auth_keys_count" | sed 's/ *//g')"
	if [[ "$auth_keys_count" -eq 0 ]]; then
		auth_results+=("pass:Authorized Keys: None")
	else
		auth_results+=("warn:Authorized Keys: ${auth_keys_count} key(s)")
		fix_issue "Authorized Keys" "rm ~/.ssh/authorized_keys"
	fi
	increment_global_progress

	update_global_progress_info "audit: Sudoers..."
	local sudoers_check
	sudoers_check="$(sudo visudo -c 2>&1)"
	if echo "$sudoers_check" | grep -qi "parsed"; then
		auth_results+=("pass:Sudoers: OK")
	else
		auth_results+=("fail:Sudoers: Error")
	fi
	increment_global_progress
	
	print_category "User & Auth" "${auth_results[@]}"
}

run_persistence_checks() {
	local -a persistence_results=()
	
	update_global_progress_info "audit: User LaunchAgents..."
	local user_la_count
	user_la_count="$(ls -1 ~/Library/LaunchAgents/ 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$user_la_count" ]] && user_la_count="0"
	user_la_count="$(echo "$user_la_count" | sed 's/ *//g')"
	if [[ "$user_la_count" -eq 0 ]]; then
		persistence_results+=("pass:User LaunchAgents: None")
	elif [[ "$user_la_count" -lt 10 ]]; then
		persistence_results+=("pass:User LaunchAgents: ${user_la_count} items")
	else
		persistence_results+=("warn:User LaunchAgents: ${user_la_count} items")
		fix_issue "User LaunchAgents" "rm -rf ~/Library/LaunchAgents/*.plist 2>/dev/null; echo 'Removed user launch agents'"
	fi
	increment_global_progress

	update_global_progress_info "audit: System LaunchAgents..."
	local sys_la_count
	sys_la_count="$(ls -1 /Library/LaunchAgents/ 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$sys_la_count" ]] && sys_la_count="0"
	sys_la_count="$(echo "$sys_la_count" | sed 's/ *//g')"
	if [[ "$sys_la_count" -eq 0 ]]; then
		persistence_results+=("pass:System LaunchAgents: None")
	elif [[ "$sys_la_count" -lt 10 ]]; then
		persistence_results+=("pass:System LaunchAgents: ${sys_la_count} items")
	else
		persistence_results+=("warn:System LaunchAgents: ${sys_la_count} items")
	fi
	increment_global_progress

	update_global_progress_info "audit: LaunchDaemons..."
	local ld_count
	ld_count="$(ls -1 /Library/LaunchDaemons/ 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$ld_count" ]] && ld_count="0"
	ld_count="$(echo "$ld_count" | sed 's/ *//g')"
	if [[ "$ld_count" -eq 0 ]]; then
		persistence_results+=("pass:LaunchDaemons: None")
	elif [[ "$ld_count" -lt 15 ]]; then
		persistence_results+=("pass:LaunchDaemons: ${ld_count} items")
	else
		persistence_results+=("warn:LaunchDaemons: ${ld_count} items")
	fi
	increment_global_progress

	update_global_progress_info "audit: Cron Jobs..."
	local cron_count
	cron_count="$(crontab -l 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$cron_count" ]] && cron_count="0"
	cron_count="$(echo "$cron_count" | sed 's/ *//g')"
	if [[ "$cron_count" -eq 0 ]]; then
		persistence_results+=("pass:Cron Jobs: None")
	else
		persistence_results+=("warn:Cron Jobs: ${cron_count} jobs")
		fix_issue "Cron Jobs" "crontab -r 2>/dev/null || true"
	fi
	increment_global_progress

	update_global_progress_info "audit: At Jobs..."
	local at_count
	at_count="$(atq 2>/dev/null | wc -l 2>/dev/null)"
	[[ -z "$at_count" ]] && at_count="0"
	at_count="$(echo "$at_count" | sed 's/ *//g')"
	if [[ "$at_count" -eq 0 ]]; then
		persistence_results+=("pass:At Jobs: None")
	else
		persistence_results+=("warn:At Jobs: ${at_count} jobs")
		fix_issue "At Jobs" "atrm -a 2>/dev/null || true"
	fi
	increment_global_progress

	update_global_progress_info "audit: Login Items..."
	local li_count
	li_count="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | wc -l 2>/dev/null)"
	[[ -z "$li_count" ]] && li_count="0"
	li_count="$(echo "$li_count" | sed 's/ *//g')"
	if [[ "$li_count" -eq 0 ]]; then
		persistence_results+=("pass:Login Items: None")
	elif [[ "$li_count" -lt 15 ]]; then
		persistence_results+=("pass:Login Items: ${li_count} items")
	else
		persistence_results+=("warn:Login Items: ${li_count} items")
		fix_issue "Login Items" "osascript -e 'tell application \"System Events\" to delete every login item' 2>/dev/null || true"
	fi
	increment_global_progress
	
	print_category "Persistence" "${persistence_results[@]}"
}

run_privacy_checks() {
	local -a privacy_results=()
	
	if [[ "$DEEP_SCAN" != "true" ]]; then
		return
	fi
	
	update_global_progress_info "audit: Location Services..."
	local location_status
	location_status="$(system_profiler SPPrivacyDataType 2>/dev/null | grep -i "Location Services" | head -1)"
	if echo "$location_status" | grep -qi "0"; then
		privacy_results+=("pass:Location Services: Disabled")
	elif echo "$location_status" | grep -qi "1"; then
		privacy_results+=("warn:Location Services: Enabled")
	else
		privacy_results+=("warn:Location Services: Unknown")
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Analytics..."
	local analytics
	analytics="$(defaults read /Library/Preferences/com.apple.usage.plist Analytics.blinded 2>/dev/null)"
	if [[ -z "$analytics" ]]; then
		privacy_results+=("pass:Analytics: Disabled")
	else
		privacy_results+=("warn:Analytics: Enabled")
	fi
	increment_global_progress
	
	print_category "Privacy" "${privacy_results[@]}"
}

run_additional_checks() {
	local -a additional_results=()
	
	update_global_progress_info "audit: XProtect..."
	local xprotect
	xprotect="$(defaults read /Library/Preferences/com.apple.XprotectFramework XProtectData 2>/dev/null | head -1)"
	if [[ -n "$xprotect" ]]; then
		additional_results+=("pass:XProtect: Active")
	else
		additional_results+=("warn:XProtect: Unknown")
	fi
	increment_global_progress
	
	update_global_progress_info "audit: Screen Lock..."
	local lock_timeout
	lock_timeout="$(defaults read /Library/Preferences/com.apple.preferencepanegeneral starttimesystem 2>/dev/null)"
	if [[ -n "$lock_timeout" ]]; then
		additional_results+=("pass:Screen Lock: ${lock_timeout}s timeout")
	else
		additional_results+=("warn:Screen Lock: Default")
		fix_issue "Screen Lock" "sudo defaults write /Library/Preferences/com.apple.screensaver askForPasswordDelay -int 0 && defaults write com.apple.screensaver askForPassword -int 1"
	fi
	increment_global_progress

	update_global_progress_info "audit: .ssh Permissions..."
	local file_perms
	file_perms="$(ls -la ~/.ssh 2>/dev/null | head -1 | awk '{print $1}')"
	if [[ "$file_perms" == "drwx------" ]]; then
		additional_results+=("pass:.ssh Permissions: Secure")
	else
		additional_results+=("warn:.ssh Permissions: Insecure")
		fix_issue ".ssh Permissions" "chmod 700 ~/.ssh && chmod 600 ~/.ssh/*"
	fi
	increment_global_progress

	update_global_progress_info "audit: Quarantined Files..."
	local quarantined
	quarantined="$(xattr -lr ~/Downloads 2>/dev/null | grep -c "com.apple.quarantine" || echo "0")"
	if [[ "$quarantined" -eq 0 ]]; then
		additional_results+=("pass:Quarantined Files: None")
	else
		additional_results+=("warn:Quarantined Files: ${quarantined}")
		fix_issue "Quarantined Files" "find ~/Downloads -xattr -r -d com.apple.quarantine 2>/dev/null || true"
	fi
	increment_global_progress

	update_global_progress_info "audit: Kernel Extensions..."
	local kext_count
	kext_count="$(kextstat 2>/dev/null | grep -v "com.apple" | wc -l 2>/dev/null | sed 's/ *//g')"
	[[ -z "$kext_count" ]] && kext_count="0"
	if [[ "$kext_count" -eq 0 ]]; then
		additional_results+=("pass:Kernel Extensions: None")
	elif [[ "$kext_count" -lt 5 ]]; then
		additional_results+=("pass:Kernel Extensions: ${kext_count} (third-party)")
	else
		additional_results+=("warn:Kernel Extensions: ${kext_count} (third-party)")
		fix_issue "Kernel Extensions" "echo 'Warning: Removing kernel extensions requires SIP disabled. Manual review recommended.'"
	fi
	increment_global_progress

	update_global_progress_info "audit: Sudo Access..."
	local sudo_last
	sudo_last="$(sudo -l 2>/dev/null | head -1)"
	if [[ -n "$sudo_last" && "$sudo_last" != "Sorry" ]]; then
		additional_results+=("pass:Sudo Access: Available")
	else
		additional_results+=("pass:Sudo Access: Limited")
	fi
	increment_global_progress

	update_global_progress_info "audit: DNS-over-HTTPS..."
	local doh
	doh="$(scutil --dns 2>/dev/null | grep "DOT" | head -1)"
	if [[ -n "$doh" ]]; then
		additional_results+=("pass:DNS-over-HTTPS: Enabled")
	else
		additional_results+=("warn:DNS-over-HTTPS: Disabled")
					FIX_QUEUE+=("DNS-over-HTTPS|MANUAL:requires manual setup in System Settings → Network → Advanced → DNS")
	fi
	increment_global_progress
	
	print_category "Additional" "${additional_results[@]}"
}

render_accumulated_results() {
	for cat_name in "${ACCUMULATED_CATEGORIES[@]}"; do
		local name_len=${#cat_name}
		local padding=$((37 - name_len))
		local pad_str
		pad_str=$(printf '%*s' "$padding" '')
		
		echo ""
		echo "+---------------------------------------+"
		echo "| ${CYAN}${cat_name}${NC}${pad_str}|"
		echo "+---------------------------------------+"
		
		for result in "${ACCUMULATED_RESULTS[@]}"; do
			local r_cat="$(echo "$result" | cut -d: -f2)"
			[[ "$r_cat" != "$cat_name" ]] && continue
			local status="$(echo "$result" | cut -d: -f1)"
			local label="$(echo "$result" | cut -d: -f3-)"
			
			local icon=""
			local colored_label=""
			if [[ "$status" == "pass" ]]; then
				icon="${GREEN}✓${NC}"
				colored_label="${GREEN}$label${NC}"
			elif [[ "$status" == "warn" ]]; then
				icon="${YELLOW}⚠${NC}"
				colored_label="${YELLOW}$label${NC}"
			elif [[ "$status" == "fail" ]]; then
				icon="${RED}✗${NC}"
				colored_label="${RED}$label${NC}"
			else
				icon="${GRAY}○${NC}"
				colored_label="${GRAY}$label${NC}"
			fi
			
			local raw_len=${#label}
			local pad_len=$((34 - raw_len))
			local ppadding
			ppadding=$(printf '%*s' "$pad_len")
			
			printf "│ %s %s%s%s │\n" "$icon" "$colored_label" "$ppadding"
		done
		
		echo "+---------------------------------------+"
	done
	
	print_summary
}

main() {
	local -a core_results=()
	local -a network_results=()
	local -a auth_results=()
	local -a persistence_results=()
	local -a privacy_results=()
	local -a additional_results=()
	
	if [[ "$SHOW_HISTORY" == "true" ]]; then
		show_audit_history
		return
	fi
	
	if [[ "$SHOW_DIFF" == "true" ]]; then
		show_diff
		return
	fi
	
	if [[ "$SCHEDULE_WEEKLY" == "true" ]]; then
		print_section_header "Schedule Weekly Audit"
		schedule_weekly
		echo ""
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return
	fi
	
	if [[ "$QUIET_MODE" == "true" ]]; then
		DEEP_SCAN=true
	fi
	
	if [[ "$DEEP_SCAN" == "true" ]]; then
		sudo -v 2>/dev/null || true
	fi
	
	local use_global_progress=false
	if [[ -t 1 && "$QUIET_MODE" != "true" && "$OUTPUT_FORMAT" == "text" && "$SHOW_HISTORY" != "true" && "$SHOW_DIFF" != "true" && "$SCHEDULE_WEEKLY" != "true" ]]; then
		if [[ "$AUTO_FIX" == "true" && "$FIX_FORCE" != "true" ]]; then
			use_global_progress=false
		else
			use_global_progress=true
		fi
	fi
	
	if [[ "$use_global_progress" == "true" ]]; then
		AUDIT_SILENT_MODE=true
		local total_checks=30
		[[ "$DEEP_SCAN" == "true" ]] && total_checks=32
		init_global_progress "$total_checks"
	fi
	
	if [[ "$QUIET_MODE" == "true" ]]; then
		{
			run_core_checks
			run_network_checks
			run_auth_checks
			run_persistence_checks
			run_privacy_checks
			run_additional_checks
		} > /dev/null 2>&1
		echo "pass:${PASS_count} warn:${WARN_count} fail:${FAIL_count}"
		return 0
	fi

	run_core_checks
	run_network_checks
	run_auth_checks
	run_persistence_checks
	run_privacy_checks
	run_additional_checks
	
	if [[ "$use_global_progress" == "true" ]]; then
		finish_global_progress
		AUDIT_SILENT_MODE=false
		render_accumulated_results
	else
		print_summary
	fi

	if [[ ${#FIX_QUEUE[@]} -gt 0 && "$AUTO_FIX" != "true" && "$OUTPUT_FORMAT" == "text" && "$QUIET_MODE" != "true" ]]; then
		echo ""
		echo -n "Fix ${#FIX_QUEUE[@]} issue(s) automatically? [y/N] "
		read -r answer
		if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
			echo ""
			for item in "${FIX_QUEUE[@]}"; do
				check_name="${item%%|*}"
				fix_cmd="${item#*|}"
				if [[ "$fix_cmd" == MANUAL:* ]]; then
					echo "  ${YELLOW}→ Fixing: $check_name${NC}"
					echo "  ${GRAY}ℹ Skipped: ${fix_cmd#MANUAL:}${NC}"
				else
					echo "  ${YELLOW}→ Fixing: $check_name${NC}"
					eval "$fix_cmd" 2>/dev/null && echo "  ${GREEN}✓ Fixed${NC}" || echo "  ${RED}✗ Fix failed${NC}"
				fi
			done
		fi
	fi

	if [[ "$NOTIFY" == "true" ]]; then
		send_notification
	fi
	
	if [[ -n "$REPORT_FILE" ]]; then
		case "$OUTPUT_FORMAT" in
			html) print_output_html > "$REPORT_FILE" ;;
			csv) print_output_csv > "$REPORT_FILE" ;;
			json) print_output_json > "$REPORT_FILE" ;;
			*) print_summary > "$REPORT_FILE" ;;
		esac
		echo "  Report saved to: $REPORT_FILE"
	fi
	
	if [[ "$OUTPUT_FORMAT" != "text" ]]; then
		case "$OUTPUT_FORMAT" in
			html) print_output_html ;;
			csv) print_output_csv ;;
			json) print_output_json ;;
		esac
		return 0
	fi
	
	save_to_history
	
	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"