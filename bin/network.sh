#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_network_help() {
	echo "Usage: rcc network [options]"
	echo ""
	echo "Show network status with multi-scan confidence scoring"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

# shellcheck disable=SC2034
	JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_network_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

# Which sections found something, out of how many ran. The old "confidence"
# counted rows against a fixed denominator of 10 and printed "14/10 scans".
sections_run=0
sections_found=0
section_done() {
	sections_run=$((sections_run + 1))
	[[ "${1:-0}" -gt 0 ]] && sections_found=$((sections_found + 1))
	return 0
}

# What an address is, by the ranges the RFCs and the tunnel vendors reserve.
# 172.16/12 is private space: the old rule's glob 172.2* called an iPhone
# hotspot's 172.20.10.3 "WireGuard", and every 2a02: global address "Other".
categorize_interface() {
	case "$1" in
		127.*|::1)                              echo "Loopback" ;;
		fe80:*|169.254.*)                       echo "LinkLocal" ;;
		fd7a:115c:a1e0:*)                       echo "Tailscale" ;;
		100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*) echo "CGNAT" ;;
		10.*|192.168.*)                         echo "Private" ;;
		172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) echo "Private" ;;
		f[cd][0-9a-f][0-9a-f]:*)                echo "ULA" ;;
		[23][0-9a-f][0-9a-f][0-9a-f]:*)         echo "Public" ;;
		*.*.*.*)                                echo "Public" ;;
		*)                                      echo "Other" ;;
	esac
}

# The service behind a listening port, where the number alone says it.
# 5000 and 7000 are the AirPlay Receiver (ControlCenter), which the old
# table called "Proxy service"; rapportd is Handoff, not Remote Desktop, and
# is not a proxy either, so it is no longer listed here at all.
categorize_port() {
	case "$1" in
		7890|7891|7892)         echo "Clash" ;;
		8080)                   echo "HTTP-Proxy" ;;
		1080|1081)              echo "SOCKS5" ;;
		8388)                   echo "Shadowsocks" ;;
		10000|10086)            echo "V2Ray/VLess" ;;
		1194|51820)             echo "WireGuard-VPN" ;;
		500|4500)               echo "IPSec" ;;
		7000|5000)              echo "AirPlay" ;;
		*)                      echo "" ;;
	esac
}

# Proxy and VPN software by process name. Apple's own transparent proxy for
# system services (/usr/libexec/networkserviceproxy) matched "proxy" and was
# reported as third-party proxy software on every Mac; it is excluded.
categorize_process() {
	case "$1" in
		*/networkserviceproxy)  echo "" ;;
		*clash*)                echo "Clash" ;;
		*surge*)               echo "Surge" ;;
		*v2ray*|*xray*)        echo "V2Ray/Xray" ;;
		*shadowsocks*|*ss-*)    echo "Shadowsocks" ;;
		*hysteria*)             echo "Hysteria" ;;
		*outline*)              echo "Outline" ;;
		*wireguard*|*wg-*)      echo "WireGuard" ;;
		*tailscale*)            echo "Tailscale" ;;
		*vpn*)                 echo "VPN" ;;
		*proxy*)               echo "Proxy" ;;
		*tunnel*)              echo "Tunnel" ;;
		*)                     echo "" ;;
	esac
}

get_latency() {
	local host="$1"
	local result
	result=$(ping -c 1 -t 2 "$host" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1 ms/' || echo "N/A")
	echo "$result"
}

# Every address on every interface, one per line: iface, family, address,
# kind. `ifconfig -l` is the list; the old code walked a hardcoded set of
# nine names and Tailscale's utun8 was not among them, so the report said
# Tailscale was connected while showing no Tailscale address. All global IPv6
# addresses are kept: the temporary one is what outbound connections use.
# Link-local ones are not: every interface has one and it says nothing.
_addresses() {
	local iface addr kind
	for iface in $(ifconfig -l 2>/dev/null); do
		while IFS= read -r addr; do
			[[ -n "$addr" ]] || continue
			kind=$(categorize_interface "$addr")
			[[ "$kind" == LinkLocal ]] && continue
			printf '%s\tinet\t%s\t%s\n' "$iface" "$addr" "$kind"
		done < <(ifconfig "$iface" 2>/dev/null | awk '$1 == "inet" {print $2}')
		while IFS= read -r addr; do
			[[ -n "$addr" ]] || continue
			addr="${addr%%%*}"
			kind=$(categorize_interface "$addr")
			[[ "$kind" == LinkLocal ]] && continue
			printf '%s\tinet6\t%s\t%s\n' "$iface" "$addr" "$kind"
		done < <(ifconfig "$iface" 2>/dev/null | awk '$1 == "inet6" {print $2}')
	done
}

# Unique resolvers, in the order scutil lists them.
_dns_servers() {
	scutil --dns 2>/dev/null | awk '/nameserver\[/ {print $3}' | awk '!seen[$0]++'
}

# name<TAB>state per configured VPN; scutil marks the live one with "*".
_vpns() {
	scutil --nc list 2>/dev/null | tail -n +2 | while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		local name state
		name=$(printf '%s' "$line" | sed 's/.*"\(.*\)".*/\1/')
		[[ -n "$name" ]] || continue
		if printf '%s' "$line" | grep -qE '^\* *\(Connected\)'; then state=connected; else state=configured; fi
		printf '%s\t%s\n' "$name" "$state"
	done
}

# Proxies in force: the environment's, and the system's from `scutil --proxy`,
# which System Settings writes and which nothing here used to read. Two were
# configured on this Mac; they happened to be off, so "[]" was right by luck.
_proxies() {
	# `|| true`: with no proxy in the environment grep exits 1, and under
	# set -e that ended the function before it asked the system.
	env 2>/dev/null | grep -iE '^[a-z_]*_proxy=' | grep -v '^_' | while IFS='=' read -r key value; do
		printf '%s\t%s\n' "$key" "$value"
	done || true
	local sys
	sys=$(scutil --proxy 2>/dev/null || true)
	local kind
	for kind in HTTP HTTPS SOCKS FTP; do
		if printf '%s\n' "$sys" | grep -qE "^ *${kind}Enable *: *1"; then
			printf 'system %s\t%s:%s\n' "$kind" \
				"$(printf '%s\n' "$sys" | awk -v k="${kind}Proxy" '$1 == k {print $3}')" \
				"$(printf '%s\n' "$sys" | awk -v k="${kind}Port" '$1 == k {print $3}')"
		fi
	done
	if printf '%s\n' "$sys" | grep -qE '^ *ProxyAutoConfigEnable *: *1'; then
		printf 'system PAC\t%s\n' "$(printf '%s\n' "$sys" | awk '$1 == "ProxyAutoConfigURLString" {print $3}')"
	fi
}

# "enabled", "disabled", or "unknown" when socketfilterfw could not answer.
# `grep -qi enabled && enabled || disabled` turned a tool that failed to run
# into a firewall reported off — and painted red.
_app_firewall() {
	local out
	if out=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null); then
		case "$out" in
			*enabled*) printf 'enabled' ;;
			*disabled*) printf 'disabled' ;;
			*) printf 'unknown' ;;
		esac
	else
		printf 'unknown'
	fi
}

_pf_state() {
	pfctl -s info 2>/dev/null | awk '/^Status/ {print tolower($2)}' | head -1 || true
}

_json_report() {
	local first iface family addr kind ns name state key value

	printf '{\n'

	# Addresses first: what this Mac is, on the network, right now.
	printf '  "interfaces": ['
	first=1
	while IFS=$'\t' read -r iface family addr kind; do
		[[ -n "$iface" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "family": %s, "address": %s, "kind": %s}' \
			"$(rcc_json_string "$iface")" "$(rcc_json_string "$family")" \
			"$(rcc_json_string "$addr")" "$(rcc_json_string "$kind")"
	done < <(_addresses)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "dns": ['
	first=1
	while IFS= read -r ns; do
		[[ -n "$ns" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$ns")"
	done < <(_dns_servers)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "vpns": ['
	first=1
	while IFS=$'\t' read -r name state; do
		[[ -n "$name" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "state": %s}' "$(rcc_json_string "$name")" "$(rcc_json_string "$state")"
	done < <(_vpns)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "proxies": ['
	first=1
	while IFS=$'\t' read -r key value; do
		[[ -n "$key" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "value": %s}' "$(rcc_json_string "$key")" "$(rcc_json_string "$value")"
	done < <(_proxies)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	local pf
	pf=$(_pf_state)
	printf '  "firewall": {"application": %s, "pf": %s},\n' \
		"$(rcc_json_string "$(_app_firewall)")" "$(rcc_json_string "${pf:-unknown}")"

	# `grep -c` prints 0 on no match AND exits 1, so `|| printf '0'` printed a
	# second one and the document became `"connections": 0\n0`.
	local established
	established=$(netstat -an -p tcp 2>/dev/null | grep -c ESTABLISHED || true)
	printf '  "connections": %s\n}\n' "$(rcc_json_number "$established")"
}

main() {
	# ifconfig, scutil and netstat live in /usr/sbin and /sbin. Without them
	# this reported an empty machine: no addresses, no DNS, no VPN, 0
	# connections, exit 0.
	rcc_require_tools ifconfig scutil netstat
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	rcc_require_tools lsof ps
	print_section_header "Network Status"

	print_section_header "[1/10] Interfaces"
	print_table_header "Name|Kind|Address" 12 12 40
	local found=0 iface family addr kind
	while IFS=$'\t' read -r iface family addr kind; do
		[[ -n "$iface" ]] || continue
		# Loopback and link-local are on every Mac and say nothing about this one.
		[[ "$kind" == "Loopback" || "$kind" == "LinkLocal" ]] && continue
		print_table_row "$iface|$kind|$addr" 12 12 40
		found=$((found + 1))
	done < <(_addresses)
	[[ $found -gt 0 ]] || echo "  ${GRAY}no addresses beyond loopback${NC}"
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[2/10] Listening Ports"
	print_table_header "Port|Service|Description" 8 15 30
	found=0
	local ports endpoints port
	# rcc_local_port reads the shape of the address rather than the last
	# colon-field, which on an IPv6 address is a hextet.
	endpoints=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep -vE "^COMMAND" | awk '{print $9}' || true)
	ports=$(
		while IFS= read -r endpoint; do
			[[ -n "$endpoint" ]] && rcc_local_port "$endpoint"
		done <<< "$endpoints" | sort -u
	)
	while IFS= read -r port; do
		[[ -n "$port" ]] || continue
		local type desc
		type=$(categorize_port "$port")
		[[ -n "$type" ]] || continue
		case "$type" in
			AirPlay) desc="AirPlay Receiver (ControlCenter), not a proxy" ;;
			Clash) desc="Proxy client" ;;
			SOCKS5) desc="SOCKS5 proxy" ;;
			HTTP-Proxy) desc="HTTP proxy" ;;
			V2Ray/VLess) desc="VMess/VLess" ;;
			Shadowsocks) desc="Shadowsocks" ;;
			IPSec) desc="IPSec VPN" ;;
			WireGuard-VPN) desc="WireGuard VPN" ;;
			*) desc="$type" ;;
		esac
		print_table_row "$port|$type|$desc" 8 15 30
		found=$((found + 1))
	done <<< "$ports"
	[[ $found -gt 0 ]] || echo "  ${GRAY}no proxy/VPN ports detected${NC}"
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[3/10] Processes"
	echo "  ${GRAY}Detected:${NC}"
	found=0
	local procs cmd detected=""
	# shellcheck disable=SC2009
	procs=$(ps -axo comm= 2>/dev/null | grep -iE "proxy|vpn|tunnel|wireguard|tailscale|shadowsock|vless|vmess|hysteria|clash|surge|outline|v2ray|xray" | sort -u || true)
	while IFS= read -r cmd; do
		[[ -n "$cmd" ]] || continue
		local type
		type=$(categorize_process "$cmd")
		[[ -n "$type" ]] || continue
		echo "    ✓ $type ${GRAY}($cmd)${NC}"
		detected+="${type},"
		found=$((found + 1))
	done <<< "$procs"
	[[ $found -gt 0 ]] || echo "  ${GRAY}no proxy/VPN processes found${NC}"
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[4/10] Proxies"
	echo "  ${GRAY}In force (environment and System Settings):${NC}"
	found=0
	local key value
	while IFS=$'\t' read -r key value; do
		[[ -n "$key" ]] || continue
		echo "    ✓ $key = $value"
		found=$((found + 1))
	done < <(_proxies)
	[[ $found -gt 0 ]] || echo "  ${GRAY}no proxy in force${NC}"
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[5/10] NO_PROXY Config"
	echo "  ${GRAY}Exclusions:${NC}"
	found=0
	local noproxy
	noproxy=$(env 2>/dev/null | grep -iE "^no_proxy=" | cut -d= -f2- || true)
	if [[ -n "$noproxy" ]]; then
		echo "    ✓ $noproxy"
		found=1
	else
		echo "  ${GRAY}no NO_PROXY configured${NC}"
	fi
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[6/10] VPNs (scutil --nc)"
	echo "  ${GRAY}Configured:${NC}"
	found=0
	local name state any=0
	while IFS=$'\t' read -r name state; do
		[[ -n "$name" ]] || continue
		any=1
		if [[ "$state" == connected ]]; then
			echo "    ✓ $name (Connected)"
			found=$((found + 1))
		else
			echo "    - $name"
		fi
	done < <(_vpns)
	[[ $any -eq 1 ]] || echo "  ${GRAY}no VPN configured${NC}"
	[[ $found -gt 0 || $any -eq 0 ]] || echo "  ${GRAY}none connected${NC}"
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[7/10] DNS Servers"
	print_table_header "Server|Label" 40 20
	found=0
	local ns label
	while IFS= read -r ns; do
		[[ -n "$ns" ]] || continue
		case "$(categorize_interface "$ns")" in
			Tailscale) label="Tailscale DNS" ;;
			Private) label="LAN / router" ;;
			LinkLocal) label="router (link-local)" ;;
			*) label="" ;;
		esac
		print_table_row "$ns|$label" 40 20
		found=$((found + 1))
	done < <(_dns_servers)
	[[ $found -gt 0 ]] || echo "  ${GRAY}none found${NC}"
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[8/10] Firewall Status"
	echo "  ${GRAY}Status:${NC}"
	found=0
	local awlf pf
	awlf=$(_app_firewall)
	if [[ "$awlf" == unknown ]]; then
		echo "    ${YELLOW}?${NC} App Firewall: not checked (socketfilterfw did not answer)"
	else
		echo "    ✓ App Firewall: $awlf"
		found=1
	fi
	pf=$(_pf_state)
	if [[ -n "$pf" ]]; then
		echo "    ✓ pf: $pf"
		found=1
	else
		echo "    ${GRAY}pf: not checked (pfctl needs administrator rights)${NC}"
	fi
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[9/10] Latency & Connections"
	local l8 l1 connections
	l8=$(get_latency "8.8.8.8")
	l1=$(get_latency "1.1.1.1")
	connections=$(netstat -an -p tcp 2>/dev/null | grep -c "ESTABLISHED" || true)
	print_table_header "Server|Latency" 12 12
	print_table_row "8.8.8.8|$l8" 12 12
	print_table_row "1.1.1.1|$l1" 12 12
	print_table_row "TCP connections|${connections:-0}" 12 12
	found=0
	[[ "$l8" != "N/A" || "$l1" != "N/A" ]] && found=1
	section_done "$found"
	echo "${GREEN}✓${NC}"

	print_section_header "[10/10] Summary"
	echo "  ${GRAY}Checks with a finding:${NC} $sections_found of $sections_run"
	local software
	software=$(printf '%s' "$detected" | tr ',' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')
	echo "  ${GRAY}Proxy/VPN software:${NC} ${software:-none}"
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
