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

# A Mac with no battery is not an error: a mini, a Studio or an iMac has
# nothing to report, and the answer is that fact. pmset prints no percentage
# there, so grep exits 1, and under `set -euo pipefail` that killed the script
# before it could say so - in text mode too, which printed nothing at all.
# Every read of the charge goes through here, and here it cannot fail.
_battery_charge() {
	pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true
}

# Where the power comes from, per pmset's first line: "ac", "battery" or
# nothing. Not the same as charging: a MacBook on its adapter with macOS
# holding the charge at 80% is on AC and not charging, and the extension
# used to call that "on battery".
_power_source() {
	local line
	line=$(pmset -g batt 2>/dev/null | head -1 || true)
	case "$line" in
		*"'AC Power'"*) printf 'ac' ;;
		*"'Battery Power'"*) printf 'battery' ;;
		*) printf '' ;;
	esac
}

_power_source_label() {
	case "$(_power_source)" in
		ac) printf 'AC adapter' ;;
		battery) printf 'Battery' ;;
		*) printf '%s' "${GRAY}not reported${NC}" ;;
	esac
}

get_battery_info() {
	local battery_info
	battery_info=$(system_profiler SPPowerDataType 2>/dev/null)

	local cycle_count
	cycle_count=$(echo "$battery_info" | grep -i "Cycle Count" | head -1 | awk '{print $NF}' | tr -d ':') || cycle_count=""

	local max_capacity
	max_capacity=$(echo "$battery_info" | grep -i "Maximum Capacity" | head -1 | awk '{print $NF}' | tr -d '%') || max_capacity=""

	local condition
	condition=$(echo "$battery_info" | grep -i "Condition" | head -1 | awk '{for(i=2;i<=NF;i++) printf "%s ", $i}' | sed 's/ *$//') || condition=""

	local is_charging
	# SPPowerDataType prints "Charging:" twice, once for the battery and once
	# for the AC charger. Without head -1 the value is two lines, the record
	# below becomes two records, and every field after this one is lost: that is
	# why this Mac reported "Fully Charged: No" while sitting at 100%.
	is_charging=$(echo "$battery_info" | grep -i "Charging:" | head -1 | awk '{print $NF}') || is_charging=""

	local is_full
	is_full=$(echo "$battery_info" | grep -i "Fully Charged:" | head -1 | awk '{print $NF}') || is_full=""

	local charge_percent
	charge_percent=$(echo "$battery_info" | \
		grep -iE "State of Charge|Current Charge" | \
		grep -oE '[0-9]+' | head -1) || charge_percent=""

	if [[ -z "$charge_percent" ]]; then
		charge_percent=$(_battery_charge)
	fi

	# Cycle count, maximum capacity and charge are battery-only: a machine that
	# reports none of the three has no battery, rather than a battery it failed
	# to describe. Charging and Fully Charged are not part of the test, because
	# a desktop on AC can answer them.
	local present="true"
	[[ -n "${cycle_count}${max_capacity}${charge_percent}" ]] || present="false"

	echo "cycle_count:$cycle_count|max_capacity:$max_capacity|condition:$condition|charging:$is_charging|full:$is_full|charge:$charge_percent|present:$present"
}

display_battery_status() {
	local data
	data=$(get_battery_info)

	local cycle_count_str max_capacity_str condition_str charging_str full_str charge_str present_str
	IFS='|' read -r cycle_count_str max_capacity_str condition_str charging_str full_str charge_str present_str <<<"$data"

	local cycle_count max_capacity condition charging full charge present
	cycle_count=$(echo "$cycle_count_str" | cut -d: -f2)
	max_capacity=$(echo "$max_capacity_str" | cut -d: -f2)
	condition=$(echo "$condition_str" | cut -d: -f2-)
	charging=$(echo "$charging_str" | cut -d: -f2)
	full=$(echo "$full_str" | cut -d: -f2)
	charge=$(echo "$charge_str" | cut -d: -f2)
	present=$(echo "$present_str" | cut -d: -f2)

	if [[ "$present" != "true" ]]; then
		print_section_header "Battery Status"
		echo "No battery: this Mac runs on AC power only"
		echo ""
		print_success "Completed"
		return 0
	fi

	if [[ -z "$charge" || "$charge" == "N/A" ]]; then
		charge=$(_battery_charge)
	fi

	# A figure system_profiler did not report is "not reported", never 0: the
	# old defaults graded a 694-cycle, 85% battery as "0 cycles, 0% (poor)"
	# whenever system_profiler was off PATH, while --json said null.
	local capacity_cell
	if [[ -n "$max_capacity" ]]; then
		local health_color health_percent
		if [[ $max_capacity -ge 80 ]]; then
			health_color="${GREEN}"; health_percent="good"
		elif [[ $max_capacity -ge 60 ]]; then
			health_color="${YELLOW}"; health_percent="fair"
		else
			health_color="${RED}"; health_percent="poor"
		fi
		capacity_cell="${health_color}${max_capacity}%${NC} (${health_percent})"
	else
		capacity_cell="${GRAY}not reported${NC}"
	fi

	print_section_header "Battery Status"

	print_table_header "Metric|Value" 15 24
	print_table_row "Cycle Count|${cycle_count:-${GRAY}not reported${NC}}" 15 24
	print_table_row "Max Capacity|${capacity_cell}" 15 24
	print_table_row "Condition|${condition:-${GRAY}not reported${NC}}" 15 24
	print_table_row "Charge Level|${charge:+${charge}%}${charge:-${GRAY}not reported${NC}}" 15 24
	print_table_row "Power Source|$(_power_source_label)" 15 24
	print_table_row "Charging|${charging:-${GRAY}not reported${NC}}" 15 24
	print_table_row "Fully Charged|${full:-${GRAY}not reported${NC}}" 15 24

	echo ""
	print_success "Completed"
}

main() {
	rcc_require_tools pmset system_profiler
	if [[ "$JSON_OUTPUT" == "true" ]]; then
		local data
		data=$(get_battery_info)

		local cycle_count_str max_capacity_str condition_str charging_str full_str charge_str present_str
		IFS='|' read -r cycle_count_str max_capacity_str condition_str charging_str full_str charge_str present_str <<<"$data"

		local cycle_count max_capacity condition charging full charge present
		cycle_count=$(echo "$cycle_count_str" | cut -d: -f2)
		max_capacity=$(echo "$max_capacity_str" | cut -d: -f2)
		condition=$(echo "$condition_str" | cut -d: -f2-)
		charging=$(echo "$charging_str" | cut -d: -f2)
		full=$(echo "$full_str" | cut -d: -f2)
		charge=$(echo "$charge_str" | cut -d: -f2)
		present=$(echo "$present_str" | cut -d: -f2)

		[[ -z "$charge" ]] && charge=$(_battery_charge)
		[[ "$charging" == "Yes" ]] && charging="true" || charging="false"
		[[ "$full" == "Yes" ]] && full="true" || full="false"

		# null, not 0. A number here is a measurement, and a Mac with no battery
		# has not measured a cycle count of zero - it has nothing to measure. The
		# same holds for a battery whose figures system_profiler did not report:
		# zero reads as a new battery, which is the opposite of unknown.
		[[ -n "$cycle_count" ]] || cycle_count="null"
		[[ -n "$max_capacity" ]] || max_capacity="null"
		[[ -n "$charge" ]] || charge="null"
		local condition_json="null"
		[[ -z "$condition" ]] || condition_json=$(printf '"%s"' "$condition")

		local power_source_json="null"
		[[ -z "$(_power_source)" ]] || power_source_json=$(printf '"%s"' "$(_power_source)")

		cat <<EOF
{
  "present": $present,
  "power_source": $power_source_json,
  "cycle_count": $cycle_count,
  "max_capacity_percent": $max_capacity,
  "condition": $condition_json,
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