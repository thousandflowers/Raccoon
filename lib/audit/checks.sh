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
		# No *manually* configured resolver is the normal DHCP case, not a
		# problem. Forcing a public DNS (e.g. Google 8.8.8.8) would override a
		# legitimate local/VPN/Tailscale setup, so report — don't "fix".
		network_results+=("pass:DNS Servers: DHCP-provided")
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
		fix_issue "Authorized Keys" "cp ~/.ssh/authorized_keys \"\$(_fix_backup_dir)/\" && rm ~/.ssh/authorized_keys"
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
		fix_issue "User LaunchAgents" "cp ~/Library/LaunchAgents/*.plist \"\$(_fix_backup_dir)/\" 2>/dev/null; rm -f ~/Library/LaunchAgents/*.plist; echo 'Removed user launch agents (backup saved)'"
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
		fix_issue "Cron Jobs" "crontab -l > \"\$(_fix_backup_dir)/crontab.txt\" 2>/dev/null; crontab -r 2>/dev/null || true"
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
		fix_issue "Login Items" "osascript -e 'tell application \"System Events\" to get the name of every login item' > \"\$(_fix_backup_dir)/login-items.txt\" 2>/dev/null; osascript -e 'tell application \"System Events\" to delete every login item' 2>/dev/null || true"
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
		# Quarantine IS Gatekeeper working as intended. Recursively stripping it
		# would bypass malware checks on un-reviewed downloads — the opposite of
		# what a security audit should do. Report only.
		additional_results+=("pass:Quarantined Files: ${quarantined} (Gatekeeper active)")
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

# _check_explain NAME -> plain-language explanation for a check, or "" if none.
# Used by `audit --explain` to print a friendly note under each fail/warn. Keyed
# by the check name (the part before ": " in a result). Bash 3.2-safe: a plain
# case, no associative arrays. A check with no entry returns "" and is simply
# left undescribed — adding a check never requires touching this table.
# Each entry: what it does · risk if it fails · how to fix, in plain words.
_check_explain() {
	case "$1" in
		FileVault)
			printf '%s' "Encrypts the whole disk with your login password. Without it, anyone with the Mac can read your files. Turn it on in System Settings -> Privacy & Security -> FileVault." ;;
		SIP)
			printf '%s' "System Integrity Protection locks core macOS files against tampering. Disabled, malware and bad installers can corrupt the system. Re-enable by running 'csrutil enable' from Recovery mode." ;;
		Firewall)
			printf '%s' "The firewall blocks unexpected incoming network connections. Off, other devices on the network can reach services on this Mac. Turn it on in System Settings -> Network -> Firewall." ;;
		Gatekeeper)
			printf '%s' "Gatekeeper allows only signed, Apple-checked apps to open. Disabled, a malicious app can run unnoticed. Re-enable by running 'sudo spctl --master-enable'." ;;
		"Stealth Mode")
			printf '%s' "Stealth mode makes the Mac ignore ping and port scans. Off, attackers can more easily discover it on a network. Enable it under the Firewall options in System Settings." ;;
		"Software Updates")
			printf '%s' "Security updates patch known holes attackers exploit. Out of date, the Mac is exposed to public vulnerabilities. Install pending updates in System Settings -> General -> Software Update." ;;
		Sharing)
			printf '%s' "Sharing services (screen, file, remote login) open the Mac to the network. Left on by accident, they are an entry point for intruders. Turn off unused ones in System Settings -> General -> Sharing." ;;
		"Screen Lock")
			printf '%s' "A screen lock asks for the password after sleep or the screensaver. Without it, anyone nearby can use an unattended Mac. Set it in System Settings -> Lock Screen." ;;
		".ssh Permissions")
			printf '%s' "Your ~/.ssh folder holds private keys and must stay private. Loose permissions let other accounts read your keys. Fix with 'chmod 700 ~/.ssh' and 'chmod 600 ~/.ssh/*'." ;;
		"DNS-over-HTTPS")
			printf '%s' "DNS-over-HTTPS encrypts the website lookups your Mac makes. Without it, the network can see and tamper with which sites you visit. Enable it in System Settings -> Network -> DNS." ;;
		"Auto-Login")
			printf '%s' "Auto-login skips the password at startup. Enabled, a stolen or rebooted Mac unlocks itself straight to your desktop. Turn it off in System Settings -> Users & Groups -> Login Options." ;;
		"SSH Daemon")
			printf '%s' "The SSH daemon lets people log into this Mac remotely over the network. On but unneeded, it is a remote-attack target. Disable Remote Login in System Settings -> General -> Sharing." ;;
		*)
			printf '%s' "" ;;
	esac
}

# _check_cis NAME -> CIS Apple macOS Benchmark recommendation for a check, or ""
# if the check has no per-machine CIS equivalent. Used by `audit --cis` to map
# Raccoon's technical checks onto the only compliance framework that audits a
# single Mac (SOC 2 / ISO 27001 / NIST CSF audit the organisation, not the
# machine, so they are intentionally out of scope). Same Bash 3.2-safe case
# pattern as _check_explain — a check with no entry returns "" and is uncounted.
#
# ponytail: section numbers track the CIS Apple macOS Benchmark (v3.x, the
# Sonoma/Sequoia line). They drift between benchmark releases; on a new release
# bump the numbers in this one table — nothing else references them.
_check_cis() {
	case "$1" in
		FileVault)        printf '%s' "2.5.1.1 — Enable FileVault" ;;
		Firewall)         printf '%s' "2.5.2.2 — Enable Firewall" ;;
		"Stealth Mode")   printf '%s' "2.5.2.3 — Enable Firewall Stealth Mode" ;;
		Gatekeeper)       printf '%s' "2.5.5 — Enable Gatekeeper" ;;
		SIP)              printf '%s' "Ensure System Integrity Protection (SIP) is enabled" ;;
		"Software Updates") printf '%s' "1.1–1.6 — Install current Apple software updates" ;;
		Bluetooth)        printf '%s' "2.1.1 — Disable Bluetooth when no devices are paired" ;;
		"Screen Lock")    printf '%s' "2.3.1 / 5.x — Require password after screensaver/sleep" ;;
		Sharing)          printf '%s' "2.4 — Disable unused sharing services" ;;
		"SSH Daemon")     printf '%s' "2.4.5 — Ensure Remote Login (SSH) is disabled" ;;
		"Auto-Login")     printf '%s' "5.6 — Ensure automatic login is disabled" ;;
		"Location Services") printf '%s' "2.6.1 — Restrict Location Services" ;;
		".ssh Permissions") printf '%s' "5.1 — Secure user file & folder permissions" ;;
		*)                printf '%s' "" ;;
	esac
}

# _check_command NAME -> the exact shell command an auditor can run to verify a
# check by hand, or "" if the check has no single reproducible command. Powers
# `audit --verbose` ("verify, don't trust"): the documented command is the
# single source of truth, shown verbatim and — under --verbose — re-run live so
# the auditor sees the raw output for themselves. Same Bash 3.2-safe case shape
# as _check_explain / _check_cis. These mirror the commands the checks actually
# run in this file; keep them in sync when a check's probe changes.
_check_command() {
	case "$1" in
		FileVault)            printf '%s' "sudo fdesetup status" ;;
		SIP)                  printf '%s' "csrutil status" ;;
		Gatekeeper)           printf '%s' "spctl --status" ;;
		Firewall)             printf '%s' "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate" ;;
		"Stealth Mode")       printf '%s' "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode" ;;
		"Software Updates")   printf '%s' "softwareupdate -l" ;;
		"Open Ports")         printf '%s' "sudo lsof -i -P -n | grep LISTEN" ;;
		"DNS Servers")        printf '%s' "scutil --dns | grep nameserver" ;;
		VPN)                  printf '%s' "networksetup -listallnetworkservices | grep VPN" ;;
		Bluetooth)            printf '%s' "blueutil status" ;;
		Sharing)              printf '%s' "sharing -l" ;;
		"SSH Daemon")         printf '%s' "sudo launchctl list com.openssh.sshd" ;;
		"Auto-Login")         printf '%s' "sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser" ;;
		Keychain)             printf '%s' "security list-keychains" ;;
		"SSH Keys")           printf '%s' "ls -la ~/.ssh/*.pub" ;;
		"Authorized Keys")    printf '%s' "cat ~/.ssh/authorized_keys" ;;
		Sudoers)              printf '%s' "sudo visudo -c" ;;
		"User LaunchAgents")  printf '%s' "ls -1 ~/Library/LaunchAgents/" ;;
		"System LaunchAgents") printf '%s' "ls -1 /Library/LaunchAgents/" ;;
		LaunchDaemons)        printf '%s' "ls -1 /Library/LaunchDaemons/" ;;
		"Cron Jobs")          printf '%s' "crontab -l" ;;
		"At Jobs")            printf '%s' "atq" ;;
		"Login Items")        printf '%s' "osascript -e 'tell application \"System Events\" to get the name of every login item'" ;;
		"Location Services")  printf '%s' "system_profiler SPPrivacyDataType | grep -i 'Location Services'" ;;
		Analytics)            printf '%s' "defaults read /Library/Preferences/com.apple.usage.plist Analytics.blinded" ;;
		XProtect)             printf '%s' "defaults read /Library/Preferences/com.apple.XprotectFramework XProtectData" ;;
		"Screen Lock")        printf '%s' "defaults read /Library/Preferences/com.apple.preferencepanegeneral starttimesystem" ;;
		".ssh Permissions")   printf '%s' "ls -la ~/.ssh" ;;
		"Quarantined Files")  printf '%s' "xattr -lr ~/Downloads | grep com.apple.quarantine" ;;
		"Kernel Extensions")  printf '%s' "kextstat | grep -v com.apple" ;;
		"Sudo Access")        printf '%s' "sudo -l" ;;
		"DNS-over-HTTPS")     printf '%s' "scutil --dns | grep DOT" ;;
		*)                    printf '%s' "" ;;
	esac
}
