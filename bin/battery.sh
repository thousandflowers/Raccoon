#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_battery_help() {
	print_help_header "battery" "Show battery health, cycle count, and charging status" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
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

	[[ -z "$charge" ]] && charge="0"
	[[ -z "$cycle_count" ]] && cycle_count="0"
	[[ -z "$max_capacity" ]] && max_capacity="0"
	[[ -z "$condition" ]] && condition="N/A"
	[[ -z "$charging" ]] && charging="No"
	[[ -z "$full" ]] && full="No"

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

	print_section_header "Battery Status"

	print_table_header "Metric|Value" 15 20
	print_table_row "Cycle Count|${cycle_count:-0}" 15 20
	print_table_row "Max Capacity|${health_color}${max_capacity}%${NC} (${health_percent})" 15 20
	print_table_row "Condition|${condition:-N/A}" 15 20
	print_table_row "Charge Level|${charge:-0}%" 15 20
	print_table_row "Charging|${charging:-No}" 15 20
	print_table_row "Fully Charged|${full:-No}" 15 20

	echo ""
	print_success "Completed"
}

main() {
	if [[ "$JSON_OUTPUT" == "true" ]]; then
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

		[[ -z "$full" ]] && full="No"
		[[ -z "$charge" ]] && charge=$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%')
		[[ -z "$charge" ]] && charge="0"
		[[ "$charging" == "Yes" ]] && charging="true" || charging="false"
		[[ "$full" == "Yes" ]] && full="true" || full="false"
		[[ -z "$cycle_count" ]] && cycle_count=0
		[[ -z "$max_capacity" ]] && max_capacity=0

		cat <<EOF
{
  "cycle_count": $cycle_count,
  "max_capacity_percent": $max_capacity,
  "condition": "$condition",
  "charging": $charging,
  "fully_charged": $full,
  "charge_percent": $charge
}
EOF
		exit 0
	fi

	display_battery_status
}

main "$@"