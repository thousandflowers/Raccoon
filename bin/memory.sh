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

# Machine-wide figures as "key=value" lines, one place for both renderings.
# "used" is wired + active + compressed: what the machine has committed. The
# old text summed every process's RSS, which counts shared pages once per
# process and read 12 GB "in use" on a machine with 8.7 GB resident.
_mem_summary() {
	local page_size total_bytes vm
	page_size=$(sysctl -n hw.pagesize)
	total_bytes=$(sysctl -n hw.memsize)
	vm=$(vm_stat)
	local wired active compressed inactive
	# vm_stat right-aligns the page count as the LAST field on each line,
	# e.g. "Pages wired down:   178539." — a fixed $3 picks up "down:".
	wired=$(printf '%s\n' "$vm" | awk '/Pages wired/ {gsub(/\./,"",$NF); print $NF}')
	active=$(printf '%s\n' "$vm" | awk '/Pages active/ {gsub(/\./,"",$NF); print $NF}')
	compressed=$(printf '%s\n' "$vm" | awk '/Pages occupied/ {gsub(/\./,"",$NF); print $NF}')
	inactive=$(printf '%s\n' "$vm" | awk '/Pages inactive/ {gsub(/\./,"",$NF); print $NF}')
	local mb=$((1024 * 1024))
	printf 'total_mb=%s\n' "$((total_bytes / mb))"
	printf 'wired_mb=%s\n' "$((${wired:-0} * page_size / mb))"
	printf 'active_mb=%s\n' "$((${active:-0} * page_size / mb))"
	printf 'cached_mb=%s\n' "$((${inactive:-0} * page_size / mb))"
	printf 'compressed_mb=%s\n' "$((${compressed:-0} * page_size / mb))"
	printf 'used_mb=%s\n' "$(((${wired:-0} + ${active:-0} + ${compressed:-0}) * page_size / mb))"
	# "vm.swapusage: total = 1024.00M  used = 512.00M  free = 512.00M"
	local swap
	swap=$(sysctl -n vm.swapusage 2>/dev/null || true)
	printf 'swap_total_mb=%s\n' "$(printf '%s' "$swap" | awk '{print int($3)}')"
	printf 'swap_used_mb=%s\n' "$(printf '%s' "$swap" | awk '{print int($6)}')"
	printf 'swap_free_mb=%s\n' "$(printf '%s' "$swap" | awk '{print int($9)}')"
}

# Processes by physical footprint: pid, footprint KB, RSS KB, executable path.
#
# `top -o mem` orders by footprint — the memory the machine pays for a process,
# compressed pages included. `ps -m` orders by RSS, which leaves compressed
# memory out entirely: the process at the top of this Mac holds 23 GB of
# footprint and 110 MB of RSS, and never appeared in the old top ten while a
# 216 MB row did. ps still supplies the path: top prints only the name.
_mem_processes() {
	local top_n="$1" pid kb rss path
	top -l 1 -o mem -n "$top_n" -stats pid,mem 2>/dev/null | awk '
		function kb(m,  u, n) {
			sub(/[+-]$/, "", m)
			u = substr(m, length(m)); n = substr(m, 1, length(m) - 1) + 0
			if (u == "G") return int(n * 1048576)
			if (u == "M") return int(n * 1024)
			if (u == "K") return int(n)
			if (u == "B") return int(n / 1024)
			return 0
		}
		NR > 1 && $1 ~ /^[0-9]+$/ { print $1 "\t" kb($2) }' |
	while IFS=$'\t' read -r pid kb; do
		IFS=' ' read -r rss path < <(ps -o rss=,comm= -p "$pid" 2>/dev/null || true)
		printf '%s\t%s\t%s\t%s\n' "$pid" "$kb" "${rss:-0}" "${path:-(exited)}"
	done
}

_json_report() {
	local key value first=1 pid kb rss path
	printf '{\n  "memory": {'
	while IFS='=' read -r key value; do
		[[ -n "$key" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    "%s": %s' "$key" "$(rcc_json_number "$value")"
	done < <(_mem_summary)
	printf '\n  },\n  "processes": ['
	first=1
	while IFS=$'\t' read -r pid kb rss path; do
		[[ -n "$pid" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"pid": %s, "footprint_kb": %s, "rss_kb": %s, "command": %s}' \
			"$pid" "$(rcc_json_number "$kb")" "$(rcc_json_number "$rss")" "$(rcc_json_string "$path")"
	done < <(_mem_processes "$TOP_N")
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

main() {
	# sysctl, vm_stat and top live in /usr/sbin and /usr/bin. Without sysctl
	# this printed "Total RAM 0 GB" and no swap at all, under a green Completed.
	rcc_require_tools sysctl vm_stat top ps
	[[ "$TOP_N" =~ ^[0-9]+$ ]] || TOP_N=10

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		_json_report
		return 0
	fi

	print_section_header "Memory Usage"

	# bash 3.2 (macOS's own) has no associative arrays; the keys are this
	# script's, so printf -v is safe.
	local key value total_mb used_mb wired_mb active_mb cached_mb compressed_mb
	local swap_total_mb swap_used_mb swap_free_mb
	while IFS='=' read -r key value; do
		[[ -n "$key" ]] && printf -v "$key" '%s' "$value"
	done < <(_mem_summary)

	print_table_header "Metric|Value" 25 15
	print_table_row "Total RAM|$((${total_mb:-0} / 1024)) GB" 25 15
	print_table_row "In use|${used_mb:-0} MB" 25 15
	print_table_row "Wired|${wired_mb:-0} MB" 25 15
	print_table_row "Active|${active_mb:-0} MB" 25 15
	print_table_row "Cached|${cached_mb:-0} MB" 25 15
	print_table_row "Compressed|${compressed_mb:-0} MB" 25 15
	print_table_row "Swap Total|${swap_total_mb:-0} MB" 25 15
	print_table_row "Swap Used|${swap_used_mb:-0} MB" 25 15
	print_table_row "Swap Free|${swap_free_mb:-0} MB" 25 15
	echo ""

	print_table_header "PID|COMMAND|FOOTPRINT (MB)|RSS (MB)" 8 30 15 10
	local pid kb rss path
	while IFS=$'\t' read -r pid kb rss path; do
		[[ -n "$pid" ]] || continue
		print_table_row "$pid|${path##*/}|$((kb / 1024))|$((rss / 1024))" 8 30 15 10
	done < <(_mem_processes "$TOP_N")
	echo ""
	print_info "Footprint is what a process costs, compressed pages included; RSS leaves those out."

	echo ""
	print_success "Completed"
}

main "$@"
