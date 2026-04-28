#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_ports_help() {
	echo "Usage: rcc ports [options]"
	echo ""
	echo "List open TCP/UDP ports with process information"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_ports_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		echo "Unknown option: $arg"
		echo "Usage: rcc ports [--json]"
		exit 1
		;;
	esac
done

display_ports_json() {
	local data
	data=$(lsof -iTCP -iUDP -nP 2>/dev/null || true)

	if [[ -z "$data" ]]; then
		echo "[]"
		return 0
	fi

	set +e

	local json
	json=$(echo "$data" | awk '
		BEGIN { first=1 }
		NR==1 && $1=="COMMAND" { next }
		{
			cmd=$1
			port=$9
			proto=$8
			state=$10
			n=split(port, a, ":")
			port = a[n]
			gsub(/[()]/, "", state)
			if (port=="" || proto=="") next
			key = port SUBSEP proto SUBSEP cmd SUBSEP state
			if (!(key in seen)) {
				seen[key]=1
				gsub(/"/, "\\\"", cmd)
				gsub(/"/, "\\\"", state)
				if (first) first=0; else printf ","
				printf "\n    {\"port\": \"%s\", \"proto\": \"%s\", \"process\": \"%s\", \"state\": \"%s\"}", port, proto, cmd, state
			}
		}
		END { print "" }
	')

	set -e

	echo "[$json"$'\n  ]'
}

main() {
	if [[ "$JSON_OUTPUT" == "true" ]]; then
		display_ports_json
		exit 0
	fi

	print_section_header "Network Ports"

	local data
	data=$(lsof -iTCP -iUDP -nP 2>/dev/null || true)

	if [[ -z "$data" ]]; then
		echo -e "  ${YELLOW}No ports found${NC}"
		return 0
	fi

	printf "  %-8s %-6s %-20s %s\n" "PORT" "PROTO" "PROCESS" "STATE"
	echo "  ────────────────────────────────────────────"

	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" == COMMAND* ]] && continue

		local port proto state cmd
		cmd=$(echo "$line" | awk '{print $1}')
		port=$(echo "$line" | awk '{print $9}' | grep -oE ':[0-9]+' | head -1 | tr -d ':')
		proto=$(echo "$line" | awk '{print $8}')
		state=$(echo "$line" | awk '{print $10}' | tr -d '()')

		[[ -z "$port" || -z "$proto" ]] && continue

		if [[ "$port" -lt 1024 ]] 2>/dev/null; then
			printf "  ${YELLOW}%-8s${NC} %-6s %-20s %s\n" "$port" "$proto" "$cmd" "${state:-}"
		else
			printf "  %-8s %-6s %-20s %s\n" "$port" "$proto" "$cmd" "${state:-}"
		fi
	done <<< "$data" | sort -u -k1,1 -k3,3

	echo ""
}

main "$@"