#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_memory_help() {
	print_help_header "memory" "Show processes sorted by memory usage" "[--json] [--top N]"
	echo "  --json             Output in JSON format"
	echo "  --top N            Show top N processes (default: 10)"
	echo ""
}

JSON_OUTPUT=false
TOP_N=10

while [[ $# -gt 0 ]]; do
	case "$1" in
	--help | -h)
		show_memory_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		shift
		;;
	--top)
		TOP_N="${2:-10}"
		shift 2
		;;
	--top=*)
		TOP_N="${1#*=}"
		shift
		;;
	*)
		shift
		;;
	esac
done

main() {
	print_section_header "Memory Usage"

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		local tmpf
		tmpf=$(mktemp)
		ps aux -m | awk -v top="$TOP_N" 'NR>1 && NR<=top+1 {printf "{\"pid\": %s, \"rss\": %s, \"command\": \"%s\"}\n", $2, $6, $11}' > "$tmpf"
		awk 'BEGIN{print "["} {if(NR>1) printf ",\n"; printf "  %s", $0} END{print "\n]"}' "$tmpf"
		rm "$tmpf"
		return 0
	fi

	print_table_header "PID|COMMAND|RSS (MB)" 8 30 10

	local -a processes=()
	while IFS= read -r line; do
		processes+=("$line")
	done < <(ps aux -m | awk -v top="$TOP_N" 'NR>1 && NR<=top+1 {print $2 "|" $11 "|" int($6/1024)}')

	for proc in "${processes[@]}"; do
		print_table_row "$proc" 8 30 10
		done

	local total_rss
	total_rss=$(ps aux -m | awk 'NR>1 {sum+=$6} END {print int(sum/1024)}')
	echo ""
	echo "| Total RSS: ${total_rss} MB |"

	echo ""
	print_success "Completed"
}

main "$@"
