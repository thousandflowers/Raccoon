#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_battery_help() {
	echo "Usage: rcc battery [options]"
	echo ""
	echo "Show battery health, cycle count, and charging status"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_battery_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		echo "Unknown option: $arg"
		echo "Usage: rcc battery [--json]"
		exit 1
		;;
	esac
done

get_battery_info() {
	local battery_info
	battery_info=$(system_profiler SPPowerDataType 2>/dev/null)

	local cycle_count
	cycle_count=$(echo "$battery_info" | grep -i "Cycle Count" | awk '{print $NF}' | tr -d ':')

	local max_capacity
	max_capacity=$(echo "$battery_info" | grep -i "Maximum Capacity" | awk '{print $NF}' | tr -d '%')

	local condition
	condition=$(echo "$battery_info" | grep -i "Condition" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i}' | sed 's/ *$//')

	local is_charging
	is_charging=$(echo "$battery_info" | grep -i "Charging:" | awk '{print $NF}')

	local is_full
	is_full=$(echo "$battery_info" | grep -i "Fully Charged:" | awk '{print $NF}')

	local charge_percent
	charge_percent=$(echo "$battery_info" | \
		grep -iE "State of Charge|Current Charge" | \
		grep -oE '[0-9]+' | head -1)

	if [[ -z "$charge_percent" ]]; then
		charge_percent=$(pmset -g batt 2>/dev/null | \
			grep -oE '[0-9]+%' | head -1 | tr -d '%')
	fi

	echo "cycle_count:$cycle_count|max_capacity:$max_capacity|condition:$condition|charging:$is_charging|full:$is_full|charge:$charge_percent"
}

get_battery_json() {
	local data
	data=$(get_battery_info)

	local cycle_count max_capacity condition charging full charge
	IFS='|' read -r cycle_count max_capacity condition charging full charge <<<"$data"

	cycle_count=$(echo "$cycle_count" | cut -d: -f2 | tr -d ' ')
	max_capacity=$(echo "$max_capacity" | cut -d: -f2 | tr -d ' ')
	condition=$(echo "$condition" | cut -d: -f2- | tr -d '"')
	charging=$(echo "$charging" | cut -d: -f2 | tr -d ' ')
	full=$(echo "$full" | cut -d: -f2 | tr -d ' ')
	charge=$(echo "$charge" | cut -d: -f2 | tr -d ' ')

	[[ -z "$full" ]] && full="No"
	[[ -z "$charge" ]] && charge=$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%')
	[[ -z "$charge" ]] && charge="0"

	local health_color="green"
	if [[ $max_capacity -lt 60 ]]; then
		health_color="red"
	elif [[ $max_capacity -lt 80 ]]; then
		health_color="yellow"
	fi

	cat <<EOF
{
  "cycle_count": $cycle_count,
  "max_capacity_percent": $max_capacity,
  "health_color": "$health_color",
  "condition": "$condition",
  "charging": $charging,
  "fully_charged": $full,
  "charge_percent": $charge
}
EOF
}

display_battery_status() {
	local data
	data=$(get_battery_info)

	local cycle_count_str max_capacity_str condition_str charging_str full_str charge_str
	IFS='|' read -r cycle_count_str max_capacity_str condition_str charging_str full_str charge_str <<<"$data"

	local cycle_count max_capacity condition charging full charge
	cycle_count=$(echo "$cycle_count_str" | cut -d: -f2)
	max_capacity=$(echo "$max_capacity_str" | cut -d: -f2)
	condition=$(echo "$condition_str" | cut -d: -f2-)
	charging=$(echo "$charging_str" | cut -d: -f2)
	full=$(echo "$full_str" | cut -d: -f2)
	charge=$(echo "$charge_str" | cut -d: -f2)

	if [[ -z "$charge" || "$charge" == "N/A" ]]; then
		charge=$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%')
	fi

	local health_color health_percent
	if [[ $max_capacity -ge 80 ]]; then
		health_color="${GREEN}"
		health_percent="good"
	elif [[ $max_capacity -ge 60 ]]; then
		health_color="${YELLOW}"
		health_percent="fair"
	else
		health_color="${RED}"
		health_percent="poor"
	fi

	print_section_header "Battery Health"
	echo "  Cycle Count:      ${cycle_count:-N/A}"
	echo "  Max Capacity:     ${health_color}${max_capacity}%${NC} (${health_percent})"
	echo "  Condition:        ${condition:-N/A}"

	print_section_header "Charge Status"
	echo "  Charge Level:     ${charge:-N/A}%"
	echo "  Charging:         ${charging:-No}"
	echo "  Fully Charged:    ${full:-No}"
}

battery_fetch() {
	get_battery_info >/dev/null 2>&1
}

battery_display() {
	display_battery_status
}

main() {
	if [[ "$JSON_OUTPUT" == "true" ]]; then
		get_battery_json
		exit 0
	fi

	print_section_header "Battery Status"

	show_progress_bar \
		"Fetch battery info:battery_fetch" \
		"Display status:battery_display"
}

main "$@"
