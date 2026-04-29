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
	echo "  --json             Output in JSON format"
	echo "  --top N            Show top N processes (default: 10)"
	echo "  --help, -h         Show this help"
}

JSON_OUTPUT=false
TOP_N=10

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_memory_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	--top)
		TOP_N="${2:-10}"
		shift
		;;
	--top=*)
		TOP_N="${arg#*=}"
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Memory Usage"

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		echo "["
		ps aux -m | awk -v top="$TOP_N" 'NR>1 && NR<=top+1 {print "  {\"pid\": "$2", \"rss\": "$6", \"command\": \""$11"\"}"}' | sed '$s/}/},\n/'
		echo "]"
		return 0
	fi

	print_table_header "PID|COMMAND|RSS (MB)" 8 30 8

	ps aux -m | awk -v top="$TOP_N" 'NR>1 && NR<=top+1 {printf "| %s | %s | %s |\n", $2, $11, $6/1024}'

	local total_rss
	total_rss=$(ps aux -m | awk 'NR>1 {sum+=$6} END {print sum/1024}')
	echo ""
	echo "| Total RSS: ${total_rss} MB |"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"