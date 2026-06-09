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
confidence_score=0

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_network_help
		exit 0
		;;
	--json)
		;;
	*)
		;;
	esac
done

add_confidence() {
	confidence_score=$((confidence_score + 1))
}

categorize_interface() {
	case "$1" in
		127.0.0.1|::1)           echo "Loopback" ;;
		fd7a:*)                     echo "Tailscale" ;;
		100.64.*)                  echo "NetBird" ;;
		10.0.*)                    echo "WireGuard" ;;
		172.16.*|172.17.*|172.18.*|172.19.*|172.2*|172.3*) echo "WireGuard" ;;
		fe80:*)                    echo "LinkLocal" ;;
		2001:*|2600:*|2a00:*|2a0d:*) echo "IPv6" ;;
		192.168.*)                 echo "LAN" ;;
		10.*)                     echo "LAN" ;;
		*)                         echo "Other" ;;
	esac
}

categorize_proxy() {
	case "$1" in
		7890|7891|7892)         echo "Clash" ;;
		8080)                   echo "HTTP-Proxy" ;;
		1080|1081)              echo "SOCKS5" ;;
		8388)                   echo "Shadowsocks" ;;
		443|444|10000|10086)    echo "V2Ray/VLess" ;;
		1194|51820)             echo "WireGuard-VPN" ;;
		500|4500)               echo "IPSec" ;;
		59096)                  echo "rapportd" ;;
		7000|5000)              echo "AirPlay" ;;
		*)                      echo "" ;;
	esac
}

categorize_process() {
	case "$1" in
		*clash*)                echo "Clash" ;;
		*surge*)               echo "Surge" ;;
		*v2ray*|*xray*)        echo "V2Ray/Xray" ;;
		*shadowsocks*|*ss-*)    echo "Shadowsocks" ;;
		*hysteria*)             echo "Hysteria" ;;
		*outline*)              echo "Outline" ;;
		*wireguard*|*wg-*)      echo "WireGuard" ;;
		*tailscale*)            echo "Tailscale" ;;
		*rapportd*)             echo "RemoteDesktop" ;;
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



main() {
	print_section_header "Network Status"

	print_section_header "[1/10] Interfaces"
	print_table_header "Name|Type|Value" 12 15 30
	for iface in lo0 en0 en1 utun0 utun1 utun2 utun3 utun4 utun5; do
		local ip
		ip=$(ifconfig "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' || true)
		if [[ -n "$ip" ]]; then
			local type
			type=$(categorize_interface "$ip")
			if [[ "$type" != "LinkLocal" && "$type" != "Loopback" ]]; then
				printf "%-12s %-15s %s\n" "$iface" "($type):" "$ip"
				add_confidence
			fi
		fi
		local ip6
		ip6=$(ifconfig "$iface" 2>/dev/null | grep "inet6 " | grep -v "fe80" | awk '{print $2}' | head -1 || true)
		if [[ -n "$ip6" ]]; then
			local type
			type=$(categorize_interface "$ip6")
			if [[ "$type" != "LinkLocal" ]]; then
				printf "%-12s %-15s %s\n" "$iface" "($type):" "$ip6"
				add_confidence
			fi
		fi
	done
	echo "${GREEN}✓${NC}"

	print_section_header "[2/10] Listening Ports"
	print_table_header "Port|Service|Description" 8 15 30
	local port_found=0
	local ports
	ports=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep -vE "^COMMAND" | awk '{print $2}' | sed 's/.*:://' | sed 's/(.*//' | sort -u || true)
	while IFS= read -r port; do
		[[ -z "$port" ]] && continue
		local type
		type=$(categorize_proxy "$port")
		if [[ -n "$type" ]]; then
			local desc=""
			case "$type" in
				rapportd) desc="Apple Remote Desktop" ;;
				Clash) desc="Proxy client" ;;
				SOCKS5) desc="SOCKS5 proxy" ;;
				HTTP-Proxy) desc="HTTP proxy" ;;
				V2Ray/VLess) desc="VMess/VLess" ;;
				Shadowsocks) desc="Shadowsocks" ;;
				*) desc="Proxy service" ;;
			esac
			printf "%-8s %-15s %s\n" "$port" "$type" "$desc"
			add_confidence
			port_found=1
		fi
	done <<< "$ports"
	if [[ $port_found -eq 0 ]]; then
		echo "  ${GRAY}no proxy/VPN ports detected${NC}"
	fi
	echo "${GREEN}✓${NC}"

	print_section_header "[3/10] Processes..."
	echo "  ${GRAY}Detected:${NC}"
	local proc_found=0
	local procs
	# shellcheck disable=SC2009
	procs=$(ps aux 2>/dev/null | grep -iE "proxy|vpn|tunnel|wireguard|tailscale|shadowsock|vless|vmess|hysteria|clash|surge|outline|v2ray|xray|rapportd" | grep -v grep | awk '{print $11}' | sort -u || true)
	while IFS= read -r cmd; do
		[[ -z "$cmd" ]] && continue
		local type
		type=$(categorize_process "$cmd")
		if [[ -n "$type" ]]; then
			echo "    ✓ $type"
			proc_found=1
			add_confidence
		fi
	done <<< "$procs"
	if [[ $proc_found -eq 0 ]]; then
		echo "  ${GRAY}no proxy/VPN processes found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	print_section_header "[4/10] Environment Proxies..."
	echo "  ${GRAY}Detected:${NC}"
	local env_found=0
	local proxies
	proxies=$(env 2>/dev/null | grep -iE "_proxy" | grep -v "^_" || true)
	while IFS='=' read -r key value; do
		[[ -z "$key" ]] && continue
		echo "    ✓ $key=$value"
		env_found=1
		add_confidence
	done <<< "$proxies"
	if [[ $env_found -eq 0 ]]; then
		echo "  ${GRAY}no environment proxies set${NC}"
	fi
	echo "${GREEN}✓${NC}"

	print_section_header "[5/10] NO_PROXY Config..."
	echo "  ${GRAY}Exclusions:${NC}"
	# shellcheck disable=SC2034
	local noproxy_found=0
	local noproxy
	noproxy=$(env 2>/dev/null | grep -i "NO_PROXY\|no_proxy" | cut -d= -f2- || true)
	if [[ -n "$noproxy" ]]; then
		echo "    ✓ $noproxy"
		add_confidence
	else
		echo "  ${GRAY}no NO_PROXY configured${NC}"
	fi
	echo "${GREEN}✓${NC}"

	print_section_header "[6/10] VPNs (scutil --nc)..."
	echo "  ${GRAY}Configured:${NC}"
	local vpn_found=0
	local vpns
	vpns=$(scutil --nc list 2>/dev/null || true)
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		if echo "$line" | grep -qE "\*.*Connected"; then
			local vpn_name
			vpn_name=$(echo "$line" | sed 's/.*"\(.*\)".*/\1/' | xargs || true)
			[[ -n "$vpn_name" ]] && echo "    ✓ $vpn_name (Connected)" && vpn_found=1 && add_confidence
		elif echo "$line" | grep -qE "VPN"; then
			local vpn_name
			vpn_name=$(echo "$line" | sed 's/.*"\(.*\)".*/\1/' | xargs || true)
			[[ -n "$vpn_name" ]] && echo "    - $vpn_name"
		fi
	done <<< "$vpns"
	if [[ $vpn_found -eq 0 ]]; then
		echo "  ${GRAY}no active VPNs${NC}"
	fi
	echo "${GREEN}✓${NC}"

	print_section_header "[7/10] DNS Servers"
	print_table_header "Server|Label" 24 30
	local dns_found=0
	local dns_list=""
	dns_list=$(scutil --dns 2>/dev/null | grep "nameserver" | head -5 | sed 's/.*: //' | sort -u || true)
	local prev=""
	while IFS= read -r ns; do
		[[ -z "$ns" || "$ns" == "$prev" ]] && continue
		prev="$ns"
		local label=""
		case "$ns" in
			fd7a:*) label="← Tailscale DNS" ;;
			192.168.*|.fritz.box) label="← Router/Fritz" ;;
			*) label="" ;;
		esac
		printf "%-24s %s\n" "$ns" "$label"
		dns_found=1
		add_confidence
	done <<< "$dns_list"
	if [[ $dns_found -eq 0 ]]; then
		echo "  ${GRAY}none found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	print_section_header "[8/10] Firewall Status..."
	echo "  ${GRAY}Status:${NC}"
	local fw_found=0
	local awlf
	awlf=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "")
	if [[ -n "$awlf" && "$awlf" != "unknown" ]]; then
		echo "    ✓ App Firewall: $awlf"
		fw_found=1
		add_confidence
	fi
	local pf
	pf=$(pfctl -s info 2>/dev/null | grep "Status" | awk '{print $2}' || echo "")
	if [[ -n "$pf" ]]; then
		echo "    ✓ pf: $pf"
		fw_found=1
		add_confidence
	fi
	if [[ $fw_found -eq 0 ]]; then
		echo "  ${GRAY}firewall not managed by pfctl${NC}"
	fi
	echo "${GREEN}✓${NC}"

	print_section_header "[9/10] Latency & Connections"
	print_table_header "Server|Latency|Status" 12 8 10
	local l8
	l8=$(get_latency "8.8.8.8")
	local l1
	l1=$(get_latency "1.1.1.1")
	local connections
	connections=$(netstat -an 2>/dev/null | grep -c "ESTABLISHED" || echo "0")
	printf "%-12s %-8s %s\n" "Server" "Latency" "Status"
	echo "${GRAY}────────────────────────────────────────${NC}"
	printf "%-12s %-8s %s\n" "8.8.8.8" "$l8" "${GREEN}✓${NC}"
	printf "%-12s %-8s %s\n" "1.1.1.1" "$l1" "${GREEN}✓${NC}"
	printf "%-24s %s\n" "Active:" "$connections connections"
	[[ "$l8" != "N/A" || "$l1" != "N/A" ]] && add_confidence
	echo "${GREEN}✓${NC}"

	print_section_header "[10/10] Summary..."
	local pct=$(( (confidence_score * 100) / 10 ))
	local level
	if [[ $pct -ge 80 ]]; then level="Certain"
	elif [[ $pct -ge 60 ]]; then level="Very High"
	elif [[ $pct -ge 40 ]]; then level="High"
	elif [[ $pct -ge 20 ]]; then level="Medium"
	elif [[ $pct -gt 0 ]]; then level="Low"
	else level="None"
	fi
	local detected=""
	detected=$(echo "$procs" 2>/dev/null | while read -r cmd; do
		type=$(categorize_process "$cmd")
		[[ -n "$type" ]] && echo "$type"
	done | sort -u | tr '\n' ',' | sed 's/,$//')
	echo "  ${GRAY}Status:${NC} $level ($confidence_score/10 scans)"
	echo "  ${GRAY}Detected:${NC} ${detected:-none}"
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"