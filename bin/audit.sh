#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/audit/checks.sh"

PASS_count=0
WARN_count=0
FAIL_count=0
declare -a FIX_QUEUE=()

# Count lines from stdin, return 0 on empty (avoids wc whitespace + null boilerplate)
count_lines() {
	local val
	val="$(cat - | wc -l 2>/dev/null)"
	echo "${val// }"
}

# ── Box drawing ────────────────────────────────────────────
# Every report row goes through _box_row so columns line up with the borders.
# Single source of truth for width avoids the hand-counted padding drift that
# made the old report ragged. Labels are ASCII so ${#plain} (bytes) == columns.
BOX_INNER=39  # columns between the two '|' borders, including 1 leading space

_box_border() {
	printf '+%s+\n' "$(printf '%*s' "$BOX_INNER" '' | tr ' ' '-')"
}

# _box_row PLAIN RENDERED — pad RENDERED so the row width matches the border.
# PLAIN is the same text without color codes / multibyte, used only for width.
_box_row() {
	local plain="$1" rendered="$2"
	# Defense-in-depth: a stray newline from a check would split the row across
	# lines and break the border. Collapse newlines so a row is always one line.
	plain="${plain//$'\n'/ }"
	rendered="${rendered//$'\n'/ }"
	local pad=$((BOX_INNER - 1 - ${#plain}))
	((pad < 0)) && pad=0
	printf '| %s%*s|\n' "$rendered" "$pad" ''
}

SUDO_AVAILABLE=true
_sudo() {
	if [[ "${SUDO_AVAILABLE:-true}" != "true" ]] && [[ "$1" != "-v" ]]; then
		return 1
	fi
	sudo "$@"
}

show_audit_help() {
	echo "Usage: rcc audit [options]"
	echo ""
	echo "Security audit: Comprehensive system security analysis"
	echo ""
	echo "Options:"
	echo "  --deep         Enable deep scan (full security audit, requires sudo)"
	echo "  --fix          Attempt to fix issues automatically"
	echo "  --fix --dry-run Show fixes without applying"
	echo "  --fix --force Apply fixes without confirmation"
	echo "  --quiet       Suppress non-essential output"
	echo "  --report FILE  Save report to file"
	echo "  --html        Output in HTML format"
	echo "  --csv         Output in CSV format"
	echo "  --json        Output in JSON format"
	echo "  --history     Show previous audit runs"
	echo "  --diff        Compare with previous run"
	echo "  --watch       Schedule weekly auto-audit"
	echo "  --alert       Alert on new issues"
	echo "  --notify      Send notification on issues"
	echo "  --help, -h    Show this help"
}

DEEP_SCAN=false
AUTO_FIX=false
FIX_DRY_RUN=false
FIX_FORCE=false
QUIET_MODE=false
REPORT_FILE=""
OUTPUT_FORMAT="text"
SHOW_HISTORY=false
SHOW_DIFF=false
SCHEDULE_WEEKLY=false
NOTIFY=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--help | -h)
		show_audit_help
		exit 0
		;;
	--deep)
		DEEP_SCAN=true
		shift
		;;
	--fix)
		AUTO_FIX=true
		shift
		;;
	--dry-run)
		FIX_DRY_RUN=true
		shift
		;;
	--force)
		FIX_FORCE=true
		shift
		;;
	--quiet | -q)
		QUIET_MODE=true
		DEEP_SCAN=true
		shift
		;;
	--report)
		REPORT_FILE="$2"
		shift 2
		;;
	--report=*)
		REPORT_FILE="${1#--report=}"
		shift
		;;
	--html)
		OUTPUT_FORMAT="html"
		shift
		;;
	--csv)
		OUTPUT_FORMAT="csv"
		shift
		;;
	--json)
		OUTPUT_FORMAT="json"
		shift
		;;
	--history)
		SHOW_HISTORY=true
		shift
		;;
	--diff)
		SHOW_DIFF=true
		shift
		;;
	--watch)
		SCHEDULE_WEEKLY=true
		shift
		;;
	--alert)
		# shellcheck disable=SC2034
		ALERT_ON_ISSUES=true
		shift
		;;
	--notify)
		NOTIFY=true
		shift
		;;
	*)
		shift
		;;
	esac
done

HISTORY_DIR="$HOME/.raccoon/audit-history"
[[ -d "$HISTORY_DIR" ]] || mkdir -p "$HISTORY_DIR"

print_result() {
	local status="$1"
	local label="$2"
	local icon=""
	local colored_label=""

	if [[ "$status" == "pass" ]]; then
		icon="${GREEN}✓${NC}"
		colored_label="${GREEN}$label${NC}"
		((PASS_count++)) || true
	elif [[ "$status" == "warn" ]]; then
		icon="${YELLOW}⚠${NC}"
		colored_label="${YELLOW}$label${NC}"
		((WARN_count++)) || true
	elif [[ "$status" == "fail" ]]; then
		icon="${RED}✗${NC}"
		colored_label="${RED}$label${NC}"
		((FAIL_count++)) || true
	else
		icon="${GRAY}○${NC}"
		colored_label="${GRAY}$label${NC}"
	fi

	# icon is 1 display column; "x " is its ASCII width stand-in for measuring.
	_box_row "x ${label}" "${icon} ${colored_label}"
}

print_category() {
	local name="$1"
	shift
	local -a items=("$@")

	echo ""
	_box_border
	_box_row "$name" "${CYAN}${name}${NC}"
	_box_border

	for item in "${items[@]}"; do
		local status="${item%%:*}" rest="${item#*:}"
		print_result "$status" "$rest"
	done

	_box_border
}

# Summary count row: label padded to 8 cols so the numbers line up.
_summary_row() {
	local color="$1" label="$2" count="$3"
	local body
	body="$(printf '%-8s %s' "$label" "$count")"
	_box_row "$body" "${color}$(printf '%-8s' "$label")${NC} $count"
}

print_summary() {
	echo ""
	_box_border
	_box_row "Summary" "${PURPLE_BOLD}Summary${NC}"
	_box_border
	_summary_row "$GREEN" "Pass" "$PASS_count"
	_summary_row "$YELLOW" "Warning" "$WARN_count"
	_summary_row "$RED" "Fail" "$FAIL_count"
	_box_border

	if [[ $FAIL_count -eq 0 && $WARN_count -eq 0 ]]; then
		_box_row "x All checks passed" "${GREEN}✓ All checks passed${NC}"
	elif [[ $FAIL_count -eq 0 ]]; then
		_box_row "x No critical issues" "${YELLOW}⚠ No critical issues${NC}"
	else
		_box_row "x Action required" "${RED}✗ Action required${NC}"
	fi

	_box_border
}

save_to_history() {
	local timestamp
	timestamp="$(date +%Y-%m-%d_%H:%M:%S)"
	local history_file="$HISTORY_DIR/audit_${timestamp}.json"
	
	cat > "$history_file" << EOF
{
  "timestamp": "$timestamp",
  "pass": $PASS_count,
  "warning": $WARN_count,
  "fail": $FAIL_count,
  "deep": $DEEP_SCAN,
  "results": []
}
EOF

	local latest_link="$HISTORY_DIR/latest.json"
	ln -sf "$history_file" "$latest_link" 2>/dev/null || true

	# Rotate: keep last 30 audit files
	find "$HISTORY_DIR" -name 'audit_*.json' -maxdepth 1 -exec ls -t {} + 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
}

show_audit_history() {
	echo "${PURPLE_BOLD}-- Audit History--${NC}"
	echo ""
	
	if [[ ! -d "$HISTORY_DIR" ]]; then
		echo "  No history found"
		return
	fi
	
	local -a history_files
	# shellcheck disable=SC2012,SC2207
	history_files=($(ls -t "$HISTORY_DIR"/audit_*.json 2>/dev/null | head -10)) || true
	
	if [[ ${#history_files[@]} -eq 0 ]]; then
		echo "  No history found"
		return
	fi
	
	for file in "${history_files[@]}"; do
		local date
		date="$(basename "$file" | sed 's/audit_//' | sed 's/.json//' | sed 's/_/ /')"
		local pass=""; local warn=""; local fail=""
		
		pass="$(grep -o '"pass": [0-9]*' "$file" | grep -o '[0-9]*' || echo "0")"
		warn="$(grep -o '"warning": [0-9]*' "$file" | grep -o '[0-9]*' || echo "0")"
		fail="$(grep -o '"fail": [0-9]*' "$file" | grep -o '[0-9]*' || echo "0")"
		
		echo "  $date"
		echo "    ${GREEN}Pass: $pass${NC} ${YELLOW}Warn: $warn${NC} ${RED}Fail: $fail${NC}"
		echo ""
	done
	
	echo "  Run 'rcc audit --deep --diff' to compare with previous"
}

show_diff() {
	echo "${PURPLE_BOLD}-- Diff with Previous Run--${NC}"
	echo ""
	
	local latest_link="$HISTORY_DIR/latest.json"
	if [[ ! -L "$latest_link" ]]; then
		echo "  No previous run found"
		return
	fi
	
	local prev_file
	prev_file="$(readlink "$latest_link")"
	
	local curr_pass="$PASS_count"
	local curr_warn="$WARN_count"
	local curr_fail="$FAIL_count"
	
	local prev_pass=0; local prev_warn=0; local prev_fail=0
	prev_pass="$(grep -o '"pass": [0-9]*' "$prev_file" | grep -o '[0-9]*' | head -1 || echo "0")"
	prev_warn="$(grep -o '"warning": [0-9]*' "$prev_file" | grep -o '[0-9]*' | head -1 || echo "0")"
	prev_fail="$(grep -o '"fail": [0-9]*' "$prev_file" | grep -o '[0-9]*' | head -1 || echo "0")"
	
	echo "  Previous: ${GREEN}Pass: $prev_pass${NC} ${YELLOW}Warn: $prev_warn${NC} ${RED}Fail: $prev_fail${NC}"
	echo "  Current:  ${GREEN}Pass: $curr_pass${NC} ${YELLOW}Warn: $curr_warn${NC} ${RED}Fail: $curr_fail${NC}"
	echo ""
	
	local pass_diff=$((curr_pass - prev_pass))
	local warn_diff=$((curr_warn - prev_warn))
	local fail_diff=$((curr_fail - prev_fail))
	
	if [[ $pass_diff -gt 0 ]]; then
		echo "  ${GREEN}↑ $pass_diff more checks passed${NC}"
	elif [[ $pass_diff -lt 0 ]]; then
		echo "  ${RED}↓ $((-pass_diff)) fewer checks passed${NC}"
	fi
	
	if [[ $warn_diff -gt 0 ]]; then
		echo "  ${YELLOW}↑ $warn_diff more warnings${NC}"
	elif [[ $warn_diff -lt 0 ]]; then
		echo "  ${GREEN}↓ $((-warn_diff)) fewer warnings${NC}"
	fi
	
	if [[ $fail_diff -gt 0 ]]; then
		echo "  ${RED}↑ $fail_diff more failures${NC}"
	elif [[ $fail_diff -lt 0 ]]; then
		echo "  ${GREEN}↓ $((-fail_diff)) fewer failures${NC}"
	fi
}

schedule_weekly() {
	local plist_file="$HOME/Library/LaunchAgents/com.raccoon.audit.plist"
	local audit_path
	audit_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/audit.sh"
	
	cat > "$plist_file" << EOFPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.raccoon.audit</string>
	<key>ProgramArguments</key>
	<array>
		<string>${audit_path}</string>
		<string>--deep</string>
		<string>--json</string>
		<string>--alert</string>
	</array>
	<key>RunAtLoad</key>
	<false/>
	<key>StartCalendarInterval</key>
	<array>
		<dict>
			<key>Weekday</key>
			<integer>0</integer>
			<key>Hour</key>
			<integer>9</integer>
			<key>Minute</key>
			<integer>0</integer>
		</dict>
	</array>
</dict>
</plist>
EOFPLIST

	launchctl load "$plist_file" 2>/dev/null || true
	echo "  Weekly audit scheduled (Sundays at 9:00 AM)"
}

send_notification() {
	if [[ $FAIL_count -gt 0 || $WARN_count -gt 0 ]]; then
		local title="Security Audit: Issues Found"
		local body="$FAIL_count failures, $WARN_count warnings"
		
		osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null || true
	fi
}

print_output_html() {
	local pass_pct=0
	local total=$((PASS_count + WARN_count + FAIL_count))
	[[ $total -gt 0 ]] && pass_pct=$((PASS_count * 100 / total))
	
	cat << EOFHTML
<!DOCTYPE html>
<html>
<head>
	<meta charset="UTF-8">
	<title>Security Audit Report</title>
	<style>
		body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; }
		h1 { color: #1d1d1f; border-bottom: 2px solid #0066cc; padding-bottom: 10px; }
		.summary { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; }
		.pass { color: #28a745; }
		.warn { color: #ffc107; }
		.fail { color: #dc3545; }
	</style>
</head>
<body>
	<h1>Security Audit Report</h1>
	<p>Generated: $(date)</p>
	<div class="summary">
		<h2>Summary</h2>
		<p class="pass">Pass: $PASS_count ($pass_pct%)</p>
		<p class="warn">Warning: $WARN_count</p>
		<p class="fail">Fail: $FAIL_count</p>
	</div>
</body>
</html>
EOFHTML
}

print_output_csv() {
	echo "Status,Category,Check,Result"
	echo "pass,Summary,$PASS_count passed"
	echo "warn,Summary,$WARN_count warnings"
	echo "fail,Summary,$FAIL_count failures"
}

print_output_json() {
	echo "{"
	echo "  \"timestamp\": \"$(date -Iseconds)\","
	echo "  \"audit_type\": \"$([ "$DEEP_SCAN" == "true" ] && echo "deep" || echo "basic")\","
	echo "  \"pass\": $PASS_count,"
	echo "  \"warning\": $WARN_count,"
	echo "  \"fail\": $FAIL_count"
	echo "}"
}

fix_issue() {
	local check_name="$1"
	local fix_cmd="$2"

	if [[ "$AUTO_FIX" == "true" ]]; then
		if [[ "$FIX_DRY_RUN" == "true" ]]; then
			echo "  ${CYAN}→ Would fix: $check_name${NC}"
			echo "    Command: $fix_cmd"
			return
		fi

		if [[ "$FIX_FORCE" != "true" ]]; then
			echo -n "  ${YELLOW}→ Fix $check_name? [y/N] ${NC}"
			read -r -n 1 -t 5 answer || answer="n"
			echo ""
			[[ "$answer" != "y" && "$answer" != "Y" ]] && return
		fi

		print_warning "Fixing: $check_name"
		if eval "$fix_cmd" 2>/dev/null; then
			print_success "Fixed $check_name"
		else
			print_error "Fix failed: $check_name"
		fi
	else
		FIX_QUEUE+=("${check_name}|${fix_cmd}")
	fi
}




main() {
	# Touch ID (pam_tid) works even when launched headless from the TUI, so try
	# it unconditionally rather than gating on a tty. Only mark sudo unavailable
	# when auth genuinely can't happen.
	if ensure_sudo; then
		SUDO_AVAILABLE=true
	else
		SUDO_AVAILABLE=false
		if [[ "$DEEP_SCAN" == "true" || "$QUIET_MODE" == "true" ]]; then
			echo "${YELLOW}⚠ sudo unavailable (Touch ID declined or no terminal) — sudo checks skipped${NC}" >&2
		fi
	fi
	
	if [[ "$SHOW_HISTORY" == "true" ]]; then
		show_audit_history
		return
	fi
	
	if [[ "$SHOW_DIFF" == "true" ]]; then
		show_diff
		return
	fi
	
	if [[ "$SCHEDULE_WEEKLY" == "true" ]]; then
		print_section_header "Schedule Weekly Audit"
		schedule_weekly
		echo ""
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return
	fi
	
	if [[ "$QUIET_MODE" == "true" ]]; then
		DEEP_SCAN=true
	fi
	
	if [[ "$DEEP_SCAN" == "true" ]]; then
		if [[ "$SUDO_AVAILABLE" != "true" ]]; then
			echo "${RED}✗ Deep scan requires sudo — skipped${NC}" >&2
			echo "${YELLOW}  Run from an interactive terminal or cache sudo first${NC}" >&2
			exit 0
		fi
	fi
	
	if [[ "$QUIET_MODE" == "true" ]]; then
		{
			run_core_checks
			run_network_checks
			run_auth_checks
			run_persistence_checks
			run_privacy_checks
			run_additional_checks
		} > /dev/null 2>&1
		echo "pass:${PASS_count} warn:${WARN_count} fail:${FAIL_count}"
		return 0
	fi

	run_core_checks
	run_network_checks
	run_auth_checks
	run_persistence_checks
	run_privacy_checks
	run_additional_checks
	
	print_summary

	if [[ ${#FIX_QUEUE[@]} -gt 0 && "$AUTO_FIX" != "true" && "$OUTPUT_FORMAT" == "text" && "$QUIET_MODE" != "true" ]]; then
		echo ""
		echo -n "Fix ${#FIX_QUEUE[@]} issue(s) automatically? [y/N] "
		read -r answer || answer="n"
		if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
			echo ""
			for item in "${FIX_QUEUE[@]}"; do
				check_name="${item%%|*}"
				fix_cmd="${item#*|}"
				if [[ "$fix_cmd" == MANUAL:* ]]; then
					echo "  ${YELLOW}→ Fixing: $check_name${NC}"
					echo "  ${GRAY}ℹ Skipped: ${fix_cmd#MANUAL:}${NC}"
				else
					print_warning "Fixing: $check_name"
					if eval "$fix_cmd" 2>/dev/null; then
					print_success "Fixed $check_name"
				else
					print_error "Fix failed: $check_name"
				fi
				fi
			done
		fi
	fi

	if [[ "$NOTIFY" == "true" ]]; then
		send_notification
	fi
	
	if [[ -n "$REPORT_FILE" ]]; then
		case "$OUTPUT_FORMAT" in
			html) print_output_html > "$REPORT_FILE" ;;
			csv) print_output_csv > "$REPORT_FILE" ;;
			json) print_output_json > "$REPORT_FILE" ;;
			*) print_summary > "$REPORT_FILE" ;;
		esac
		echo "  Report saved to: $REPORT_FILE"
	fi
	
	if [[ "$OUTPUT_FORMAT" != "text" ]]; then
		case "$OUTPUT_FORMAT" in
			html) print_output_html ;;
			csv) print_output_csv ;;
			json) print_output_json ;;
		esac
		return 0
	fi
	
	save_to_history
	
	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi