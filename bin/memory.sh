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

	# ponytail: system memory from vm_stat + sysctl, not parsing every vm_stat field
	local page_size total_mem vm_stat_out
	page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
	total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
	vm_stat_out=$(vm_stat 2>/dev/null || true)

	if [[ -n "$vm_stat_out" ]]; then
		local pages_wired pages_active pages_compressed pages_inactive
		# vm_stat right-aligns the page count as the LAST field on each line,
		# e.g. "Pages wired down:   178539." — taking a fixed $3/$5 picks up
		# label words ("down:") and breaks the later arithmetic under set -u.
		pages_wired=$(echo "$vm_stat_out" | grep "Pages wired" | awk '{print $NF}' | tr -d '.' || true)
		pages_active=$(echo "$vm_stat_out" | grep "Pages active" | awk '{print $NF}' | tr -d '.' || true)
		pages_compressed=$(echo "$vm_stat_out" | grep "Pages occupied" | awk '{print $NF}' | tr -d '.' || true)
		pages_inactive=$(echo "$vm_stat_out" | grep "Pages inactive" | awk '{print $NF}' | tr -d '.' || true)

		local total_gb wired_mb active_mb compressed_mb cached_mb
		total_gb=$((total_mem / 1024 / 1024 / 1024))
		[[ -n "$pages_wired" ]] && wired_mb=$((pages_wired * page_size / 1024 / 1024)) || wired_mb=0
		[[ -n "$pages_active" ]] && active_mb=$((pages_active * page_size / 1024 / 1024)) || active_mb=0
		[[ -n "$pages_compressed" ]] && compressed_mb=$((pages_compressed * page_size / 1024 / 1024)) || compressed_mb=0
		[[ -n "$pages_inactive" ]] && cached_mb=$((pages_inactive * page_size / 1024 / 1024)) || cached_mb=0

		print_table_header "Metric|Value" 25 15
		print_table_row "Total RAM|${total_gb} GB" 25 15
		print_table_row "Wired|${wired_mb} MB" 25 15
		print_table_row "Active|${active_mb} MB" 25 15
		print_table_row "Cached|${cached_mb} MB" 25 15
		print_table_row "Compressed|${compressed_mb} MB" 25 15

		# ponytail: swap from sysctl vm.swapusage, not parsing swap file details
		local swap_out swap_total swap_used swap_avail
		swap_out=$(sysctl vm.swapusage 2>/dev/null || true)
		if [[ -n "$swap_out" ]]; then
			# sysctl: "vm.swapusage: total = 1024.00M  used = 512.00M  free = 512.00M"
			# the numbers are $4/$7/$10; $3/$6/$9 are the "=" signs.
			swap_total=$(echo "$swap_out" | awk '{print $4}' | tr -d 'M')
			swap_used=$(echo "$swap_out" | awk '{print $7}' | tr -d 'M')
			swap_avail=$(echo "$swap_out" | awk '{print $10}' | tr -d 'M')
			print_table_row "Swap Total|${swap_total} MB" 25 15
			print_table_row "Swap Used|${swap_used} MB" 25 15
			print_table_row "Swap Free|${swap_avail} MB" 25 15
		fi
		echo ""
	fi

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		local tmpf
		tmpf=$(mktemp)
		# Expand $tmpf now to capture path (intentional SC2064)
	# shellcheck disable=SC2064
	trap "rm -f '$tmpf'" EXIT
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
