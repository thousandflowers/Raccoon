#!/bin/bash
set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=lib/core/common.sh
source "$SCRIPT_DIR/../lib/core/common.sh"

show_wifi_help() {
	echo "Usage: rcc wifi [options]"
	echo ""
	echo "Wi-Fi interface, active network, known networks, and saved passwords"
	echo ""
	echo "Options:"
	echo "  --active        Show only the active connection"
	echo "  --known         Show only saved (known) networks"
	echo "  --passwords     Reveal saved passwords from Keychain (no prompt)"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
	echo ""
	echo "Examples:"
	echo "  rcc wifi"
	echo "  rcc wifi --known"
	echo "  rcc wifi --passwords     # reveal Keychain passwords without prompting"
}

# The first Wi-Fi hardware port. Empty when the Mac has none: that is an
# answer, and a guessed "en0" was not.
_wifi_interface() {
	networksetup -listallhardwareports 2>/dev/null |
		awk '/Wi-Fi|AirPort/{found=1} found && /Device:/{print $2; exit}' || true
}

# The link as the interface itself reports it: "<ssid>" US "<connected>"
# (unit separator, not a tab: a tab is IFS whitespace, and an empty name
# would let `read` slide the flag into the name's place).
#
# `networksetup -getairportnetwork` says "not associated" when macOS withholds
# the network name from command-line tools (it does, without Location Services
# access, since macOS 14). That is not the same as not connected: the link is
# up and DHCP is bound, only the name is hidden. So the link state comes from
# ipconfig, and the name from whichever of the two will say it.
_active_link() {
	local iface="$1" ssid summary up=false
	ssid="$(networksetup -getairportnetwork "$iface" 2>/dev/null |
		sed -n 's/^Current Wi-Fi Network: //p' || true)"
	summary="$(ipconfig getsummary "$iface" 2>/dev/null || true)"
	if [[ -z "$ssid" ]]; then
		ssid="$(printf '%s\n' "$summary" | sed -n 's/^[[:space:]]*SSID : //p' | head -1)"
		[[ "$ssid" == "<redacted>" ]] && ssid=""
	fi
	if [[ -n "$ssid" ]] || printf '%s\n' "$summary" | grep -q 'LinkStatusActive : TRUE'; then
		up=true
	fi
	printf '%s\x1f%s\n' "$ssid" "$up"
}

# Saved (preferred) networks, one per line.
_known_networks() {
	networksetup -listpreferredwirelessnetworks "$1" 2>/dev/null |
		tail -n +2 | sed 's/^[[:space:]]*//' || true
}

_password_for() {
	security find-generic-password -D "AirPort network password" -a "$1" -w 2>/dev/null || true
}

HIDDEN_SSID_NOTE="macOS withholds the network name from command-line tools without Location Services access"

# --- sections ----------------------------------------------------------------
section_active() {
	local iface="$1" ssid up
	print_section_header "Active Connection"
	IFS=$'\x1f' read -r ssid up < <(_active_link "$iface")
	if [[ -n "$ssid" ]]; then
		print_table_row "SSID: $ssid"
	elif [[ "$up" == true ]]; then
		print_table_row "Connected, name withheld"
		print_table_row "${GRAY}${HIDDEN_SSID_NOTE}${NC}"
	else
		print_table_row "${GRAY}Not connected${NC}"
	fi
}

section_known() {
	local iface="$1" nets count=0 line
	print_section_header "Known Networks"
	nets="$(_known_networks "$iface")"
	if [[ -n "$nets" ]]; then
		while IFS= read -r line; do
			[[ -z "$line" ]] && continue
			print_table_row "$line"
			count=$((count + 1))
		done <<< "$nets"
		print_table_row "${GRAY}Total: $count saved${NC}"
	else
		print_table_row "${GRAY}No saved networks.${NC}"
	fi
}

# Passwords are sensitive: only shown with --passwords, or after an explicit y on
# a TTY. Non-tty without --passwords skips silently.
section_passwords() {
	local iface="$1" reveal="$2" nets line pw answer
	if [[ "$reveal" != "true" ]]; then
		if [[ -t 0 ]]; then
			printf '%s' "⚠ Reveal saved passwords? [y/N] "
			read -r -n 1 -t 10 answer || answer="n"
			echo ""
			[[ "$answer" == "y" || "$answer" == "Y" ]] || return 0
		else
			return 0
		fi
	fi
	print_section_header "Saved Passwords"
	nets="$(_known_networks "$iface")"
	[[ -z "$nets" ]] && { print_table_row "${GRAY}No saved networks.${NC}"; return 0; }
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		pw="$(_password_for "$line")"
		[[ -z "$pw" ]] && pw="(not found)"
		print_table_row "$line: $pw"
	done <<< "$nets"
}

output_json() {
	local iface="$1" reveal="$2" ssid up nets line pw first=1 hidden=false
	IFS=$'\x1f' read -r ssid up < <(_active_link "$iface")
	[[ "$up" == true && -z "$ssid" ]] && hidden=true
	nets="$(_known_networks "$iface")"
	printf '{\n'
	printf '  "interface": %s,\n' "$(rcc_json_string "$iface")"
	printf '  "active_ssid": %s,\n' "$(rcc_json_string "$ssid")"
	printf '  "connected": %s,\n' "$up"
	printf '  "ssid_hidden": %s,\n' "$hidden"
	printf '  "known_networks": ['
	if [[ -n "$nets" ]]; then
		while IFS= read -r line; do
			[[ -z "$line" ]] && continue
			if [[ $first -eq 1 ]]; then first=0; else printf ','; fi
			printf '\n    %s' "$(rcc_json_string "$line")"
		done <<< "$nets"
		printf '\n  '
	fi
	printf '],\n'
	printf '  "passwords": {'
	if [[ "$reveal" == "true" && -n "$nets" ]]; then
		first=1
		while IFS= read -r line; do
			[[ -z "$line" ]] && continue
			pw="$(_password_for "$line")"
			if [[ $first -eq 1 ]]; then first=0; else printf ','; fi
			printf '\n    %s: %s' "$(rcc_json_string "$line")" "$(rcc_json_string "$pw")"
		done <<< "$nets"
		printf '\n  '
	fi
	printf '}\n'
	printf '}\n'
}

main() {
	local mode_active=false mode_known=false reveal=false json=false
	for arg in "$@"; do
		case "$arg" in
			--help | -h) show_wifi_help; exit 0 ;;
			--active) mode_active=true ;;
			--known) mode_known=true ;;
			--passwords) reveal=true ;;
			--json) json=true ;;
			*) ;;
		esac
	done

	# Both live in /usr/sbin. Without them this used to print "en0", "Not
	# connected" and "No saved networks" with exit 0, on a Mac with 167 saved.
	rcc_require_tools networksetup ipconfig

	local iface
	iface="$(_wifi_interface)"

	if [[ "$json" == "true" ]]; then
		output_json "$iface" "$reveal"
		return 0
	fi

	echo ""
	if [[ -z "$iface" ]]; then
		echo "${GRAY}No Wi-Fi interface on this Mac.${NC}"
		return 0
	fi
	echo "${GRAY}Interface: $iface${NC}"

	# No explicit section flag -> show everything.
	if [[ "$mode_active" == "false" && "$mode_known" == "false" ]]; then
		section_active "$iface"
		section_known "$iface"
		section_passwords "$iface" "$reveal"
		return 0
	fi

	[[ "$mode_active" == "true" ]] && section_active "$iface"
	[[ "$mode_known" == "true" ]] && section_known "$iface"
	return 0
}

main "$@"
