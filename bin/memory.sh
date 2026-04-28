#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_memory_help() {
	echo "Usage: rcc memory [options]"
	echo ""
	echo "Show processes sorted by memory usage"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_memory_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Memory Usage"

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		echo "["
		ps aux -m | awk 'NR>1 {print "  {\"pid\": "$2", \"rss\": "$6", \"command\": \""$11"\"}"}' | head -10 | sed '$s/}/},\n/'
		echo "]"
		return 0
	fi

	printf "%-8s %-20s %s\n" "PID" "COMMAND" "RSS"
	echo "${GRAY}────────────────────────────────────────${NC}"

	ps aux -m | awk 'NR>1 {printf "%-8s %-20s %s MB\n", $2, $11, $6/1024}' | head -10

	local total_rss
	total_rss=$(ps aux -m | awk 'NR>1 {sum+=$6} END {print sum/1024}')
	echo ""
	echo "  Total RSS: ${total_rss} MB"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"