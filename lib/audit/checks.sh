# shellcheck shell=bash
# Audit check functions
# Sourced by bin/audit.sh — expects _sudo(), fix_issue(), print_category()
# and global vars DEEP_SCAN, FIX_QUEUE to be defined.

run_core_checks() {
	local -a core_results=()
	
	local fv_status
	fv_status="$(_sudo fdesetup status 2>/dev/null | grep -i "filevault is" | head -1)" || true
	if echo "$fv_status" | grep -qi "enabled"; then
		core_results+=("pass:FileVault: Enabled")
	elif echo "$fv_status" | grep -qi "disabled"; then
		core_results+=("fail:FileVault: Disabled")
		fix_issue "FileVault" "_sudo fdesetup enable -user \\$(whoami)"
	else
		core_results+=("warn:FileVault: Unknown")
	fi
	
	local sip_status
	sip_status="$(_sudo csrutil status 2>/dev/null)" || true
	if echo "$sip_status" | grep -qi "enabled"; then
		core_results+=("pass:SIP: Enabled")
	elif echo "$sip_status" | grep -qi "disabled"; then
		core_results+=("fail:SIP: Disabled")
	else
		core_results+=("warn:SIP: Unknown")
	fi
	
	local gk_status
	gk_status="$(spctl --status 2>/dev/null)" || true
	if echo "$gk_status" | grep -qi "enabled"; then
		core_results+=("pass:Gatekeeper: Enabled")
	else
		core_results+=("fail:Gatekeeper: Disabled")
		fix_issue "Gatekeeper" "_sudo spctl --master-enable"
	fi
	
	local fw_status
	fw_status="$(_sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)" || true
	if echo "$fw_status" | grep -qi "enabled"; then
		core_results+=("pass:Firewall: Enabled")
	else
		core_results+=("fail:Firewall: Disabled")
		fix_issue "Firewall" "_sudo /usr/libexec/ApplicationFirewall/socketfilterfw --enable"
	fi
	
	local stealth_status
	stealth_status="$(_sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null)" || true
	if echo "$stealth_status" | grep -qi "enabled"; then
		core_results+=("pass:Stealth Mode: Enabled")
	else
		core_results+=("warn:Stealth Mode: Disabled")
		fix_issue "Stealth Mode" "_sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"
	fi
	
	# softwareupdate -l output varies across macOS versions; the stable
	# sentinel is "No new software available", and each pending update is a
	# line beginning with "* ". The old grep for "Recommended Update" never
	# matched modern output, so it always reported "Up to date".
	local sw_output
	sw_output="$(softwareupdate -l 2>&1)" || true
	if echo "$sw_output" | grep -qi "No new software available"; then
		core_results+=("pass:Software Updates: Up to date")
	elif echo "$sw_output" | grep -qE '^[[:space:]]*\* '; then
		local updates
		updates="$(echo "$sw_output" | grep -cE '^[[:space:]]*\* ')"
		core_results+=("warn:Software Updates: ${updates} pending")
	else
		core_results+=("warn:Software Updates: Unable to determine")
	fi
	
	print_category "Core Security" "${core_results[@]}"
}

run_network_checks() {
	local -a network_results=()
	
	update_global_progress_info "audit: Open Ports..."
	port_count="$(_sudo lsof -i -P -n 2>/dev/null | grep -c LISTEN)" || true
	[[ -z "$port_count" ]] && port_count="0"
	port_count="${port_count// }"
	if [[ "$port_count" -lt 10 ]]; then
		network_results+=("pass:Open Ports: ${port_count} listening")
	else
		network_results+=("warn:Open Ports: ${port_count} listening")
		fix_issue "Open Ports" "echo 'Consider reviewing open ports with: _sudo lsof -i -P -n'"
	fi

	local dns_servers
	dns_servers="$(scutil --dns 2>/dev/null | grep "nameserver" | head -1 | awk '{print $NF}')" || true
	if [[ -n "$dns_servers" ]]; then
		network_results+=("pass:DNS Servers: ${dns_servers}")
	else
		network_results+=("warn:DNS Servers: None configured")
		fix_issue "DNS Servers" "networksetup -setdnsservers Wi-Fi 8.8.8.8"
	fi

	local vpn_count
	vpn_count="$(networksetup -listallnetworkservices 2>/dev/null | grep -c "VPN" 2>/dev/null)" || true
	[[ -z "$vpn_count" ]] && vpn_count="0"
	if [[ "$vpn_count" -eq 0 ]]; then
		network_results+=("pass:VPN: None configured")
	else
		network_results+=("warn:VPN: ${vpn_count} configured")
		fix_issue "VPN" "for svc in \$(networksetup -listallnetworkservices | grep VPN); do networksetup -disconnectvpn \"\$svc\" 2>/dev/null; done"
	fi

	local bt_status
	bt_status="$(blueutil status 2>/dev/null)" || true
	if echo "$bt_status" | grep -qi "off"; then
		network_results+=("pass:Bluetooth: Off")
	elif echo "$bt_status" | grep -qi "powered on"; then
		if echo "$bt_status" | grep -qi "discoverable"; then
			network_results+=("fail:Bluetooth: On & discoverable")
		else
			network_results+=("pass:Bluetooth: On")
		fi
		fix_issue "Bluetooth" "_sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0 && _sudo killall -HUP blued 2>/dev/null || true"
	else
		network_results+=("warn:Bluetooth: Unknown")
		fix_issue "Bluetooth" "_sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0 && _sudo killall -HUP blued 2>/dev/null || true"
	fi

	local sharing_count
	sharing_count="$(sharing -l 2>/dev/null | grep -c "Share" 2>/dev/null)" || true
	[[ -z "$sharing_count" ]] && sharing_count="0"
	if [[ "$sharing_count" -eq 0 ]]; then
		network_results+=("pass:Sharing: None enabled")
	else
		network_results+=("warn:Sharing: ${sharing_count} enabled")
		fix_issue "Sharing" "_sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null; _sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null; _sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist 2>/dev/null; true"
	fi

	local sshd_check
	sshd_check="$(_sudo launchctl list com.openssh.sshd 2>/dev/null)" || true
	if [[ -z "$sshd_check" ]] || echo "$sshd_check" | grep -q "not found"; then
		network_results+=("pass:SSH Daemon: Disabled")
	else
		network_results+=("warn:SSH Daemon: Running")
		fix_issue "SSH Daemon" "_sudo launchctl unload /System/Library/LaunchDaemons/sshd.plist"
	fi
	
	print_category "Network" "${network_results[@]}"
}

run_auth_checks() {
	local -a auth_results=()
	
	local auto_user
	auto_user="$(_sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null)" || true
	if [[ -z "$auto_user" ]]; then
		auth_results+=("pass:Auto-Login: Disabled")
	else
		auth_results+=("fail:Auto-Login: User ${auto_user}")
		fix_issue "Auto-Login" "_sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser"
	fi
	
	local keychains
	keychains="$(security list-keychains 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$keychains" ]] && keychains="0"
	keychains="${keychains// }"
	if [[ "$keychains" -gt 0 ]]; then
		auth_results+=("pass:Keychain: ${keychains} available")
	else
		auth_results+=("warn:Keychain: None found")
	fi
	
	local ssh_key_count
	# shellcheck disable=SC2012
	ssh_key_count="$(ls -la ~/.ssh/*.pub 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$ssh_key_count" ]] && ssh_key_count="0"
	ssh_key_count="${ssh_key_count// }"
	if [[ "$ssh_key_count" -eq 0 ]]; then
		auth_results+=("pass:SSH Keys: None")
	else
		auth_results+=("pass:SSH Keys: ${ssh_key_count} key(s)")
	fi
	
	local auth_keys_count
	auth_keys_count="$(cat ~/.ssh/authorized_keys 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$auth_keys_count" ]] && auth_keys_count="0"
	auth_keys_count="${auth_keys_count// }"
	if [[ "$auth_keys_count" -eq 0 ]]; then
		auth_results+=("pass:Authorized Keys: None")
	else
		auth_results+=("warn:Authorized Keys: ${auth_keys_count} key(s)")
		fix_issue "Authorized Keys" "rm ~/.ssh/authorized_keys"
	fi

	local sudoers_check
	sudoers_check="$(_sudo visudo -c 2>&1)" || true
	if echo "$sudoers_check" | grep -qi "parsed"; then
		auth_results+=("pass:Sudoers: OK")
	else
		auth_results+=("fail:Sudoers: Error")
	fi
	
	print_category "User & Auth" "${auth_results[@]}"
}

run_persistence_checks() {
	local -a persistence_results=()
	
	local user_la_count
	# shellcheck disable=SC2012
	user_la_count="$(ls -1 ~/Library/LaunchAgents/ 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$user_la_count" ]] && user_la_count="0"
	user_la_count="${user_la_count// }"
	if [[ "$user_la_count" -eq 0 ]]; then
		persistence_results+=("pass:User LaunchAgents: None")
	elif [[ "$user_la_count" -lt 10 ]]; then
		persistence_results+=("pass:User LaunchAgents: ${user_la_count} items")
	else
		persistence_results+=("warn:User LaunchAgents: ${user_la_count} items")
		fix_issue "User LaunchAgents" "rm -rf ~/Library/LaunchAgents/*.plist 2>/dev/null; echo 'Removed user launch agents'"
	fi

	local sys_la_count
	# shellcheck disable=SC2012
	sys_la_count="$(ls -1 /Library/LaunchAgents/ 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$sys_la_count" ]] && sys_la_count="0"
	sys_la_count="${sys_la_count// }"
	if [[ "$sys_la_count" -eq 0 ]]; then
		persistence_results+=("pass:System LaunchAgents: None")
	elif [[ "$sys_la_count" -lt 10 ]]; then
		persistence_results+=("pass:System LaunchAgents: ${sys_la_count} items")
	else
		persistence_results+=("warn:System LaunchAgents: ${sys_la_count} items")
	fi

	local ld_count
	# shellcheck disable=SC2012
	ld_count="$(ls -1 /Library/LaunchDaemons/ 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$ld_count" ]] && ld_count="0"
	ld_count="${ld_count// }"
	if [[ "$ld_count" -eq 0 ]]; then
		persistence_results+=("pass:LaunchDaemons: None")
	elif [[ "$ld_count" -lt 15 ]]; then
		persistence_results+=("pass:LaunchDaemons: ${ld_count} items")
	else
		persistence_results+=("warn:LaunchDaemons: ${ld_count} items")
	fi

	local cron_count
	cron_count="$(crontab -l 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$cron_count" ]] && cron_count="0"
	cron_count="${cron_count// }"
	if [[ "$cron_count" -eq 0 ]]; then
		persistence_results+=("pass:Cron Jobs: None")
	else
		persistence_results+=("warn:Cron Jobs: ${cron_count} jobs")
		fix_issue "Cron Jobs" "crontab -r 2>/dev/null || true"
	fi

	local at_count
	at_count="$(atq 2>/dev/null | wc -l 2>/dev/null)" || true
	[[ -z "$at_count" ]] && at_count="0"
	at_count="${at_count// }"
	if [[ "$at_count" -eq 0 ]]; then
		persistence_results+=("pass:At Jobs: None")
	else
		persistence_results+=("warn:At Jobs: ${at_count} jobs")
		fix_issue "At Jobs" "atrm -a 2>/dev/null || true"
	fi

	local li_count
	li_count="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | wc -l 2>/dev/null)" || true
	[[ -z "$li_count" ]] && li_count="0"
	li_count="${li_count// }"
	if [[ "$li_count" -eq 0 ]]; then
		persistence_results+=("pass:Login Items: None")
	elif [[ "$li_count" -lt 15 ]]; then
		persistence_results+=("pass:Login Items: ${li_count} items")
	else
		persistence_results+=("warn:Login Items: ${li_count} items")
		fix_issue "Login Items" "osascript -e 'tell application \"System Events\" to delete every login item' 2>/dev/null || true"
	fi
	
	print_category "Persistence" "${persistence_results[@]}"
}

run_privacy_checks() {
	local -a privacy_results=()
	
	if [[ "$DEEP_SCAN" != "true" ]]; then
		return
	fi
	
	local location_status
	location_status="$(system_profiler SPPrivacyDataType 2>/dev/null | grep -i "Location Services" | head -1)" || true
	if echo "$location_status" | grep -qi "0"; then
		privacy_results+=("pass:Location Services: Disabled")
	elif echo "$location_status" | grep -qi "1"; then
		privacy_results+=("warn:Location Services: Enabled")
	else
		privacy_results+=("warn:Location Services: Unknown")
	fi
	
	local analytics
	analytics="$(defaults read /Library/Preferences/com.apple.usage.plist Analytics.blinded 2>/dev/null)" || true
	if [[ -z "$analytics" ]]; then
		privacy_results+=("pass:Analytics: Disabled")
	else
		privacy_results+=("warn:Analytics: Enabled")
	fi
	
	print_category "Privacy" "${privacy_results[@]}"
}

run_additional_checks() {
	local -a additional_results=()
	
	local xprotect
	xprotect="$(defaults read /Library/Preferences/com.apple.XprotectFramework XProtectData 2>/dev/null | head -1)" || true
	if [[ -n "$xprotect" ]]; then
		additional_results+=("pass:XProtect: Active")
	else
		additional_results+=("warn:XProtect: Unknown")
	fi
	
	local lock_timeout
	lock_timeout="$(defaults read /Library/Preferences/com.apple.preferencepanegeneral starttimesystem 2>/dev/null)" || true
	if [[ -n "$lock_timeout" ]]; then
		additional_results+=("pass:Screen Lock: ${lock_timeout}s timeout")
	else
		additional_results+=("warn:Screen Lock: Default")
		fix_issue "Screen Lock" "_sudo defaults write /Library/Preferences/com.apple.screensaver askForPasswordDelay -int 0 && defaults write com.apple.screensaver askForPassword -int 1"
	fi

	local file_perms
	# shellcheck disable=SC2012
	file_perms="$(ls -la ~/.ssh 2>/dev/null | head -1 | awk '{print $1}')" || true
	if [[ "$file_perms" == "drwx------" ]]; then
		additional_results+=("pass:.ssh Permissions: Secure")
	else
		additional_results+=("warn:.ssh Permissions: Insecure")
		fix_issue ".ssh Permissions" "chmod 700 ~/.ssh && chmod 600 ~/.ssh/*"
	fi

	local quarantined
	# grep -c already prints 0 on no match (and exits 1); `|| echo 0` would
	# append a SECOND 0, producing "0\n0" and breaking the report row.
	quarantined="$(xattr -lr ~/Downloads 2>/dev/null | grep -c "com.apple.quarantine" || true)"
	if [[ "$quarantined" -eq 0 ]]; then
		additional_results+=("pass:Quarantined Files: None")
	else
		additional_results+=("warn:Quarantined Files: ${quarantined}")
		fix_issue "Quarantined Files" "find ~/Downloads -xattr -r -d com.apple.quarantine 2>/dev/null || true"
	fi

	local kext_count
	kext_count="$(kextstat 2>/dev/null | grep -cv "com.apple")" || true
	[[ -z "$kext_count" ]] && kext_count="0"
	if [[ "$kext_count" -eq 0 ]]; then
		additional_results+=("pass:Kernel Extensions: None")
	elif [[ "$kext_count" -lt 5 ]]; then
		additional_results+=("pass:Kernel Extensions: ${kext_count} (third-party)")
	else
		additional_results+=("warn:Kernel Extensions: ${kext_count} (third-party)")
		fix_issue "Kernel Extensions" "echo 'Warning: Removing kernel extensions requires SIP disabled. Manual review recommended.'"
	fi

	local sudo_last
	sudo_last="$(_sudo -l 2>/dev/null | head -1)" || true
	if [[ -n "$sudo_last" && "$sudo_last" != "Sorry" ]]; then
		additional_results+=("pass:Sudo Access: Available")
	else
		additional_results+=("pass:Sudo Access: Limited")
	fi

	local doh
	doh="$(scutil --dns 2>/dev/null | grep "DOT" | head -1)" || true
	if [[ -n "$doh" ]]; then
		additional_results+=("pass:DNS-over-HTTPS: Enabled")
	else
		additional_results+=("warn:DNS-over-HTTPS: Disabled")
				FIX_QUEUE+=("DNS-over-HTTPS|MANUAL:requires manual setup in System Settings → Network → Advanced → DNS")
	fi
	
	print_category "Additional" "${additional_results[@]}"
}
