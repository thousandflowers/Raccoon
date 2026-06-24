#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/audit/checks.sh"
# shellcheck source=lib/core/report.sh
source "$SCRIPT_DIR/../lib/core/report.sh"

PASS_count=0
WARN_count=0
FAIL_count=0

# Single source of truth for the data-driven reporters. Every check flows
# through print_category, which appends one TAB record per result here. The
# Markdown/RTF renderers consume ONLY this array — no check is hardcoded.
declare -a AUDIT_RESULTS=()

# Branding (optional) and system context for client-ready reports.
REPORT_CLIENT=""
REPORT_SHOP=""
REPORT_TECH=""
declare -a FIX_QUEUE=()

# Fixes that mutate user data snapshot the original here first, so a wrong
# auto-fix is recoverable. Created lazily (only when a fix actually runs).
FIX_BACKUP_DIR="$HOME/.raccoon/fix-backups/$(date +%Y%m%d-%H%M%S)"
# Per-machine opt-out: check names listed in ~/.raccoon/audit.conf are never
# auto-fixed. A config that looks unusual on one Mac may be legitimate on another.
FIX_SKIP=""

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
	echo "  --explain     Add plain-language notes under failing/warning checks"
	echo "  --remediation Client-facing intervention report (found/fixed/to-do)"
	echo "  --baseline    Save the current state as a signed reference baseline"
	echo "  --baseline-diff   Compare the current state against the baseline"
	echo "  --baseline-reset  Remove the saved baseline"
	echo "  --md          Output a client-ready Markdown report"
	echo "  --rtf         Output a client-ready RTF report (opens in TextEdit/Word)"
	echo "  --client NAME Client name for the report header (optional)"
	echo "  --shop NAME   Shop/company name for branding (optional)"
	echo "  --tech NAME   Technician name for the report header (optional)"
	echo "  --history     Show previous audit runs"
	echo "  --diff        Compare with previous run"
	echo "  --watch       Schedule weekly auto-audit"
	echo "  --alert       Send a native macOS notification when issues are found"
	echo "  --notify      Send a native macOS notification with the result"
	echo "  --help, -h    Show this help"
	echo ""
	echo "Examples:"
	echo "  rcc audit --md --report client.md --client \"Jane Doe\" \\"
	echo "            --shop \"MacFix Pro\" --tech \"Mario Rossi\""
	echo "  rcc audit --rtf --report client.rtf --shop \"MacFix Pro\""
	echo "  rcc audit --md                 # Markdown to stdout (pipeable)"
	echo "  rcc audit --explain            # audit with plain-language notes"
	echo "  rcc audit --deep --explain     # deep scan, explained"
	echo ""
	echo "Safety:"
	echo "  Destructive fixes snapshot originals to ~/.raccoon/fix-backups/ first."
	echo "  Opt a machine out of specific fixes: list check names in"
	echo "  ~/.raccoon/audit.conf (one per line, # for comments)."
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
ALERT_ON_ISSUES=false
EXPLAIN_MODE=false
REMEDIATION_MODE=false
BASELINE_SAVE=false
BASELINE_DIFF=false
BASELINE_RESET=false

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
	--md)
		OUTPUT_FORMAT="md"
		shift
		;;
	--rtf)
		OUTPUT_FORMAT="rtf"
		shift
		;;
	--client)
		REPORT_CLIENT="$2"
		shift 2
		;;
	--client=*)
		REPORT_CLIENT="${1#--client=}"
		shift
		;;
	--shop)
		REPORT_SHOP="$2"
		shift 2
		;;
	--shop=*)
		REPORT_SHOP="${1#--shop=}"
		shift
		;;
	--tech)
		REPORT_TECH="$2"
		shift 2
		;;
	--tech=*)
		REPORT_TECH="${1#--tech=}"
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
	--explain)
		EXPLAIN_MODE=true
		shift
		;;
	--remediation)
		REMEDIATION_MODE=true
		shift
		;;
	--baseline)
		BASELINE_SAVE=true
		shift
		;;
	--baseline-diff)
		BASELINE_DIFF=true
		shift
		;;
	--baseline-reset)
		BASELINE_RESET=true
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

# An explicit --md/--rtf/--json/--csv/--html flag wins. If none was given but a
# --report file carries a known extension, infer the format from it so
# `--report client.md` just works.
if [[ "$OUTPUT_FORMAT" == "text" && -n "$REPORT_FILE" ]]; then
	case "$REPORT_FILE" in
		*.md | *.markdown) OUTPUT_FORMAT="md" ;;
		*.rtf)             OUTPUT_FORMAT="rtf" ;;
		*.json)            OUTPUT_FORMAT="json" ;;
		*.csv)             OUTPUT_FORMAT="csv" ;;
		*.html | *.htm)    OUTPUT_FORMAT="html" ;;
	esac
fi

HISTORY_DIR="$HOME/.raccoon/audit-history"
[[ -d "$HISTORY_DIR" ]] || mkdir -p "$HISTORY_DIR"

BASELINE_FILE="$HOME/.raccoon/baseline.json"

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

	# --explain: print a plain-language note under failing/warning checks. Only
	# for text output (never pollutes json/csv/md/rtf). A check with no entry
	# prints nothing — the explanation is always optional.
	if [[ "${EXPLAIN_MODE:-false}" == "true" && "$OUTPUT_FORMAT" == "text" ]] &&
		{ [[ "$status" == "fail" ]] || [[ "$status" == "warn" ]]; }; then
		local check_name="${label%%: *}"
		local explanation
		explanation="$(_check_explain "$check_name")"
		if [[ -n "$explanation" ]]; then
			printf '  %s-> %s%s\n' "$GRAY" "$explanation" "$NC"
		fi
	fi
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
		# Capture into the single data model consumed by every reporter. This is
		# the one funnel all checks pass through, so md/rtf/etc stay decoupled
		# from the check list automatically.
		AUDIT_RESULTS+=("${status}"$'\t'"${name}"$'\t'"${rest}")
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

# Minimal JSON string escaping: backslash and double-quote. Check labels are
# short single-line strings, so this is sufficient and dependency-free.
_json_escape() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	printf '%s' "$s"
}

# Build the per-check results JSON from the in-memory AUDIT_RESULTS model, so a
# later --diff / --remediation can compare individual checks, not just counts.
# Emits "" when there are no results (backward-compatible empty array).
_results_json() {
	[[ ${#AUDIT_RESULTS[@]} -eq 0 ]] && return 0
	local entry st cat_ tail_ rest nm val first=1
	for entry in "${AUDIT_RESULTS[@]}"; do
		st="${entry%%$'\t'*}"
		tail_="${entry#*$'\t'}"
		cat_="${tail_%%$'\t'*}"
		rest="${tail_#*$'\t'}"
		if [[ "$rest" == *": "* ]]; then
			nm="${rest%%: *}"
			val="${rest#*: }"
		else
			nm="$rest"
			val=""
		fi
		if [[ $first -eq 1 ]]; then first=0; else printf ','; fi
		printf '\n    {"status": "%s", "category": "%s", "name": "%s", "value": "%s"}' \
			"$(_json_escape "$st")" "$(_json_escape "$cat_")" \
			"$(_json_escape "$nm")" "$(_json_escape "$val")"
	done
	printf '\n  '
}

# Write the current audit state (counts + per-check results) as JSON to a file.
# Shared by history snapshots and the signed baseline so both have one format.
_write_audit_json() {
	local file="$1" timestamp results_json
	timestamp="$(date +%Y-%m-%d_%H:%M:%S)"
	results_json="$(_results_json)"
	cat > "$file" << EOF
{
  "timestamp": "$timestamp",
  "pass": $PASS_count,
  "warning": $WARN_count,
  "fail": $FAIL_count,
  "deep": $DEEP_SCAN,
  "results": [$results_json]
}
EOF
}

save_to_history() {
	local timestamp
	timestamp="$(date +%Y-%m-%d_%H:%M:%S)"
	local history_file="$HISTORY_DIR/audit_${timestamp}.json"

	_write_audit_json "$history_file"

	local latest_link="$HISTORY_DIR/latest.json"
	ln -sf "$history_file" "$latest_link" 2>/dev/null || true

	# Rotate: keep last 30 audit files
	find "$HISTORY_DIR" -name 'audit_*.json' -maxdepth 1 -exec ls -t {} + 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
}

# Baseline: a signed reference snapshot. Later audits compare against it with
# --baseline-diff to surface regressions since that moment (not just the last run).
save_baseline() {
	mkdir -p "$HOME/.raccoon"
	_write_audit_json "$BASELINE_FILE"
	echo "${GREEN}✓ Baseline salvato — $(date)${NC}"
}

show_baseline_diff() {
	if [[ ! -f "$BASELINE_FILE" ]]; then
		echo "Nessun baseline trovato. Esegui prima rcc audit --baseline."
		return 0
	fi
	local bdate
	bdate="$(grep -o '"timestamp": "[^"]*"' "$BASELINE_FILE" | head -1 | sed 's/.*"timestamp": "\([^"]*\)".*/\1/')"
	show_diff "$BASELINE_FILE" "-- Confronto con baseline del ${bdate} --"
}

baseline_reset() {
	if [[ ! -f "$BASELINE_FILE" ]]; then
		echo "Nessun baseline da rimuovere."
		return 0
	fi
	local answer
	printf 'Rimuovere il baseline? [y/N] '
	read -r answer || answer="n"
	if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
		rm -f "$BASELINE_FILE"
		echo "Baseline rimosso."
	fi
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

# Look up a check's status inside a history file's "results" array (one JSON
# object per line). Prints the status or "" if the check is absent. Uses fixed-
# string grep + sed, no jq.
_prev_check_status() {
	local name="$1" file="$2"
	grep -F "\"name\": \"$name\"" "$file" 2>/dev/null |
		sed -n 's/.*"status": "\([^"]*\)".*/\1/p' | head -1 || true
}

show_diff() {
	# Optional args: $1 = file to compare against (default: latest history),
	# $2 = custom header. Lets --baseline-diff reuse this against baseline.json.
	local prev_file="${1:-}" header="${2:-}"
	if [[ -n "$header" ]]; then
		echo "${PURPLE_BOLD}${header}${NC}"
	else
		echo "${PURPLE_BOLD}-- Diff with Previous Run--${NC}"
	fi
	echo ""

	if [[ -z "$prev_file" ]]; then
		local latest_link="$HISTORY_DIR/latest.json"
		if [[ ! -L "$latest_link" ]]; then
			echo "  No previous run found"
			return
		fi
		prev_file="$(readlink "$latest_link")"
	fi

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

	# Per-check changes — only when the previous run recorded individual results
	# AND the current run produced them. Pre-feature histories (results: []) fall
	# back to the counter summary above, so this is fully backward compatible.
	if grep -q '"name":' "$prev_file" 2>/dev/null && [[ ${#AUDIT_RESULTS[@]} -gt 0 ]]; then
		echo ""
		echo "  ${PURPLE_BOLD}Changes by check:${NC}"
		local entry st nm tail_ rest prev
		for entry in "${AUDIT_RESULTS[@]}"; do
			st="${entry%%$'\t'*}"
			tail_="${entry#*$'\t'}"
			rest="${tail_#*$'\t'}"
			if [[ "$rest" == *": "* ]]; then nm="${rest%%: *}"; else nm="$rest"; fi
			prev="$(_prev_check_status "$nm" "$prev_file")"
			[[ -z "$prev" ]] && continue
			if [[ "$st" == "pass" && ( "$prev" == "fail" || "$prev" == "warn" ) ]]; then
				echo "  ${GREEN}✓ $nm resolved${NC}"
			elif [[ ( "$st" == "fail" || "$st" == "warn" ) && "$prev" == "pass" ]]; then
				echo "  ${RED}✗ $nm regressed${NC}"
			elif [[ ( "$st" == "fail" || "$st" == "warn" ) && ( "$prev" == "fail" || "$prev" == "warn" ) ]]; then
				echo "  ${YELLOW}⚠ $nm still needs attention${NC}"
			fi
		done
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
		<string>--alert</string>
		<string>--notify</string>
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
	local title body subtitle
	if [[ $FAIL_count -gt 0 ]]; then
		title="🦝 Raccoon — Problemi critici"
		subtitle="$FAIL_count problemi, $WARN_count avvisi"
		body="Esegui 'rcc audit --explain' per i dettagli"
	elif [[ $WARN_count -gt 0 ]]; then
		title="🦝 Raccoon — Attenzione"
		subtitle="$WARN_count avvisi"
		body="Esegui 'rcc audit' per i dettagli"
	else
		title="🦝 Raccoon — Tutto OK"
		subtitle="Tutti i check passati"
		body=""
	fi
	osascript -e "display notification \"$body\" with title \"$title\" subtitle \"$subtitle\"" 2>/dev/null || true
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

# Lazily create and echo the per-run backup dir. Same path on every call within
# a run, so multiple snapshots from one fix command land in the same folder.
_fix_backup_dir() {
	mkdir -p "$FIX_BACKUP_DIR" 2>/dev/null || true
	echo "$FIX_BACKUP_DIR"
}

# Load the per-machine fix opt-out list (one check name per line, # comments).
load_fix_skips() {
	local conf="$HOME/.raccoon/audit.conf"
	[[ -f "$conf" ]] || return 0
	FIX_SKIP="$(grep -v '^[[:space:]]*#' "$conf" | grep -v '^[[:space:]]*$' || true)"
}

# True when CHECK_NAME is opted out of auto-fix by ~/.raccoon/audit.conf.
# ponytail: exact-name skip list. Add per-value baselines (expected DNS, etc.)
# only if someone actually needs finer control than "fix this / don't".
_fix_skipped() {
	[[ -n "$FIX_SKIP" ]] && grep -Fxq "$1" <<<"$FIX_SKIP"
}

fix_issue() {
	local check_name="$1"
	local fix_cmd="$2"

	# Per-machine opt-out wins over everything: never queue, never apply.
	if _fix_skipped "$check_name"; then
		[[ "$QUIET_MODE" != "true" ]] && echo "  ${GRAY}ℹ Skipped (audit.conf): $check_name${NC}"
		return
	fi

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
		# No 2>/dev/null: a failing fix must show why, not vanish silently.
		if eval "$fix_cmd"; then
			print_success "Fixed $check_name"
		else
			print_error "Fix failed: $check_name"
		fi
	else
		FIX_QUEUE+=("${check_name}|${fix_cmd}")
	fi
}




# Client-facing remediation report: what was found, what got fixed since the
# last run, and what still needs doing. Plain text to stdout; for --md/--rtf the
# caller uses the full report renderers instead. Reads the current AUDIT_RESULTS
# and the previous history file (resolved = was fail/warn, now pass). Works with
# no history (the "resolved" section is just empty).
print_remediation() {
	local host date_str version prev_file=""
	host="$(hostname 2>/dev/null || echo unknown)"
	date_str="$(date '+%Y-%m-%d %H:%M')"
	version="$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo '?')"
	local latest_link="$HISTORY_DIR/latest.json"
	[[ -L "$latest_link" ]] && prev_file="$(readlink "$latest_link" 2>/dev/null || echo '')"

	echo "Raccoon — Rapporto intervento"
	echo "Data: $date_str · Host: $host"
	echo ""

	local entry st nm tail_ rest prev

	echo "Problemi trovati:"
	local found=0
	for entry in ${AUDIT_RESULTS[@]+"${AUDIT_RESULTS[@]}"}; do
		st="${entry%%$'\t'*}"; tail_="${entry#*$'\t'}"; rest="${tail_#*$'\t'}"
		if [[ "$rest" == *": "* ]]; then nm="${rest%%: *}"; else nm="$rest"; fi
		if [[ "$st" == "fail" || "$st" == "warn" ]]; then
			echo "  - $nm"
			found=$((found + 1))
		fi
	done
	[[ $found -eq 0 ]] && echo "  (nessuno)"
	echo ""

	echo "Problemi risolti:"
	local resolved=0
	if [[ -n "$prev_file" && -f "$prev_file" ]] && grep -q '"name":' "$prev_file" 2>/dev/null; then
		for entry in ${AUDIT_RESULTS[@]+"${AUDIT_RESULTS[@]}"}; do
			st="${entry%%$'\t'*}"; tail_="${entry#*$'\t'}"; rest="${tail_#*$'\t'}"
			if [[ "$rest" == *": "* ]]; then nm="${rest%%: *}"; else nm="$rest"; fi
			if [[ "$st" == "pass" ]]; then
				prev="$(_prev_check_status "$nm" "$prev_file")"
				if [[ "$prev" == "fail" || "$prev" == "warn" ]]; then
					echo "  - $nm"
					resolved=$((resolved + 1))
				fi
			fi
		done
	fi
	[[ $resolved -eq 0 ]] && echo "  (nessuno, o nessuna run precedente)"
	echo ""

	echo "Da completare:"
	local todo=0
	for entry in ${AUDIT_RESULTS[@]+"${AUDIT_RESULTS[@]}"}; do
		st="${entry%%$'\t'*}"; tail_="${entry#*$'\t'}"; rest="${tail_#*$'\t'}"
		if [[ "$rest" == *": "* ]]; then nm="${rest%%: *}"; else nm="$rest"; fi
		if [[ "$st" == "fail" || "$st" == "warn" ]]; then
			echo "  - $nm"
			todo=$((todo + 1))
		fi
	done
	[[ $todo -eq 0 ]] && echo "  (nessuno)"
	echo ""
	echo "Generato da Raccoon v$version"
}

# Populate system context for client-ready reports. The commercial model name
# (e.g. "MacBook Pro") via system_profiler costs ~0.3s, so this only runs for
# md/rtf output; the hw.model identifier (e.g. "MacBookPro18,3") is kept as a
# secondary field.
_set_report_context() {
	REPORT_DATE="$(date '+%Y-%m-%d %H:%M')"
	REPORT_OS="$(sw_vers -productVersion 2>/dev/null || true)"
	REPORT_MODEL_ID="$(sysctl -n hw.model 2>/dev/null || true)"
	REPORT_MODEL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2; exit}')"
	if [[ -z "$REPORT_MODEL" ]]; then
		REPORT_MODEL="$REPORT_MODEL_ID"
	fi
}

main() {
	load_fix_skips

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
	
	if [[ "$BASELINE_RESET" == "true" ]]; then
		baseline_reset
		return
	fi

	if [[ "$SHOW_DIFF" == "true" ]]; then
		# Run the checks quietly so the per-check diff has current data; the box
		# output is suppressed and only the diff summary is printed.
		{
			run_core_checks
			run_network_checks
			run_auth_checks
			run_persistence_checks
			run_privacy_checks
			run_additional_checks
		} > /dev/null 2>&1
		show_diff
		return
	fi

	if [[ "$BASELINE_DIFF" == "true" ]]; then
		# Quiet run so AUDIT_RESULTS holds the current state to compare against
		# the saved baseline.
		{
			run_core_checks
			run_network_checks
			run_auth_checks
			run_persistence_checks
			run_privacy_checks
			run_additional_checks
		} > /dev/null 2>&1
		show_baseline_diff
		return
	fi

	if [[ "$REMEDIATION_MODE" == "true" ]]; then
		# Quiet run so AUDIT_RESULTS is populated without dumping the audit boxes.
		{
			run_core_checks
			run_network_checks
			run_auth_checks
			run_persistence_checks
			run_privacy_checks
			run_additional_checks
		} > /dev/null 2>&1
		if [[ "$OUTPUT_FORMAT" == "md" || "$OUTPUT_FORMAT" == "rtf" ]]; then
			_set_report_context
		fi
		if [[ -n "$REPORT_FILE" ]]; then
			case "$OUTPUT_FORMAT" in
				md) render_report_md > "$REPORT_FILE" ;;
				rtf) render_report_rtf > "$REPORT_FILE" ;;
				*) print_remediation > "$REPORT_FILE" ;;
			esac
			echo "  Report saved to: $REPORT_FILE"
		else
			case "$OUTPUT_FORMAT" in
				md) render_report_md ;;
				rtf) render_report_rtf ;;
				*) print_remediation ;;
			esac
		fi
		return 0
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

	if [[ "$BASELINE_SAVE" == "true" ]]; then
		save_baseline
	fi

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
					# No 2>/dev/null: surface why a fix failed.
					if eval "$fix_cmd"; then
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

	# --alert: notify only when there is something to act on.
	if [[ "$ALERT_ON_ISSUES" == "true" && ( $FAIL_count -gt 0 || $WARN_count -gt 0 ) ]]; then
		send_notification
	fi

	if [[ "$OUTPUT_FORMAT" == "md" || "$OUTPUT_FORMAT" == "rtf" ]]; then
		_set_report_context
	fi

	if [[ -n "$REPORT_FILE" ]]; then
		case "$OUTPUT_FORMAT" in
			html) print_output_html > "$REPORT_FILE" ;;
			csv) print_output_csv > "$REPORT_FILE" ;;
			json) print_output_json > "$REPORT_FILE" ;;
			md) render_report_md > "$REPORT_FILE" ;;
			rtf) render_report_rtf > "$REPORT_FILE" ;;
			*) print_summary > "$REPORT_FILE" ;;
		esac
		echo "  Report saved to: $REPORT_FILE"
	fi

	if [[ "$OUTPUT_FORMAT" != "text" ]]; then
		case "$OUTPUT_FORMAT" in
			html) print_output_html ;;
			csv) print_output_csv ;;
			json) print_output_json ;;
			md) render_report_md ;;
			rtf) render_report_rtf ;;
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