#!/bin/bash
set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=lib/core/common.sh
source "$SCRIPT_DIR/../lib/core/common.sh"

AIRPORT="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

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

# Detect the Wi-Fi interface (en0 as a sane fallback).
_wifi_interface() {
	local iface
	iface="$(networksetup -listallhardwareports 2>/dev/null |
		awk '/Wi-Fi|AirPort/{found=1} found && /Device:/{print $2; exit}' || true)"
	[[ -z "$iface" ]] && iface="en0"
	printf '%s' "$iface"
}

_active_ssid() {
	networksetup -getairportnetwork "$1" 2>/dev/null |
		sed -n 's/^Current Wi-Fi Network: //p' || true
}

# Saved (preferred) networks, one per line.
_known_networks() {
	networksetup -listpreferredwirelessnetworks "$1" 2>/dev/null |
		tail -n +2 | sed 's/^[[:space:]]*//' || true
}

_password_for() {
	security find-generic-password -D "AirPort network password" -a "$1" -w 2>/dev/null || true
}

_json_escape() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	printf '%s' "$s"
}

# --- sections ----------------------------------------------------------------
section_active() {
	local iface="$1" ssid
	print_section_header "Active Connection"
	ssid="$(_active_ssid "$iface")"
	if [[ -n "$ssid" ]]; then
		print_table_row "SSID: $ssid"
		if [[ -x "$AIRPORT" ]]; then
			"$AIRPORT" -I 2>/dev/null |
				grep -E "^[[:space:]]*(SSID|RSSI|channel|lastTxRate)" |
				sed 's/^[[:space:]]*//' | while IFS= read -r line; do
				print_table_row "$line"
			done || true
		fi
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
		print_table_row "${GRAY}Nessuna rete salvata.${NC}"
	fi
}

# Passwords are sensitive: only shown with --passwords, or after an explicit y on
# a TTY. Non-tty without --passwords skips silently.
section_passwords() {
	local iface="$1" reveal="$2" nets line pw answer
	if [[ "$reveal" != "true" ]]; then
		if [[ -t 0 ]]; then
			printf '%s' "⚠ Mostrare le password salvate? [y/N] "
			read -r -n 1 -t 10 answer || answer="n"
			echo ""
			[[ "$answer" == "y" || "$answer" == "Y" ]] || return 0
		else
			return 0
		fi
	fi
	print_section_header "Saved Passwords"
	nets="$(_known_networks "$iface")"
	[[ -z "$nets" ]] && { print_table_row "${GRAY}Nessuna rete salvata.${NC}"; return 0; }
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		pw="$(_password_for "$line")"
		[[ -z "$pw" ]] && pw="(non trovata)"
		print_table_row "$line: $pw"
	done <<< "$nets"
}

output_json() {
	local iface="$1" reveal="$2" ssid nets line pw first=1
	ssid="$(_json_escape "$(_active_ssid "$iface")")"
	nets="$(_known_networks "$iface")"
	printf '{\n'
	printf '  "interface": "%s",\n' "$(_json_escape "$iface")"
	printf '  "active_ssid": "%s",\n' "$ssid"
	printf '  "known_networks": ['
	if [[ -n "$nets" ]]; then
		while IFS= read -r line; do
			[[ -z "$line" ]] && continue
			if [[ $first -eq 1 ]]; then first=0; else printf ','; fi
			printf '\n    "%s"' "$(_json_escape "$line")"
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
			printf '\n    "%s": "%s"' "$(_json_escape "$line")" "$(_json_escape "$pw")"
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

	local iface
	iface="$(_wifi_interface)"

	if [[ "$json" == "true" ]]; then
		output_json "$iface" "$reveal"
		return 0
	fi

	echo ""
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
