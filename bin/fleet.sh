#!/bin/bash
set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=lib/core/common.sh
source "$SCRIPT_DIR/../lib/core/common.sh"
# shellcheck source=lib/core/report.sh
source "$SCRIPT_DIR/../lib/core/report.sh"
# shellcheck source=lib/audit/checks.sh
source "$SCRIPT_DIR/../lib/audit/checks.sh"   # for _check_explain

FLEET_CONF="$HOME/.raccoon/fleet.conf"
FLEET_HISTORY="$HOME/.raccoon/fleet-history"
HOSTS_FILE="$FLEET_CONF"
PARALLEL=5
FLEET_TIMEOUT="${FLEET_TIMEOUT:-30}"
OUTPUT_FORMAT="text"
REPORT_FILE=""
EXPLAIN=false

# Aggregation state (consumed by report.sh render_fleet_*). Bash 3.2: no
# associative arrays — one TAB record per host plus per-host result files.
HOSTS=()
PORTS=()
PROFILES=()
FLEET_ROWS=()
FLEET_RESULTS_DIR=""
FLEET_COUNT=0
FLEET_REACHED=0
FLEET_UNREACHABLE=0
FLEET_TOTAL_PASS=0
FLEET_TOTAL_WARN=0
FLEET_TOTAL_FAIL=0
TMP_DIR=""
BUNDLE_FILE=""

show_fleet_help() {
	echo "Usage: rcc fleet <command> [options]"
	echo ""
	echo "Run security audits across multiple Macs over SSH (key auth only)."
	echo ""
	echo "Commands:"
	echo "  audit            Audit every host (default)"
	echo "  status           Quick SSH reachability check"
	echo "  add <host>       Add a host to fleet.conf"
	echo "  remove <host>    Remove a host from fleet.conf"
	echo "  list             List configured hosts"
	echo ""
	echo "Options (audit):"
	echo "  --hosts FILE     Use an alternate hosts file (default: ~/.raccoon/fleet.conf)"
	echo "  --parallel N     Max simultaneous connections (default: 5)"
	echo "  --report FILE    Save an aggregate report (.md or .rtf)"
	echo "  --json           Output structured JSON"
	echo "  --explain        Plain-language notes for hosts with issues"
	echo "  --help, -h       Show this help"
	echo ""
	echo "fleet.conf: one host per line (# comments), e.g.:"
	echo "  mario@192.168.1.10"
	echo "  reception@192.168.1.20 --profile reception"
	echo "  admin@office.example.com:2222"
	echo ""
	echo "Remote Macs need only bash, macOS, and an SSH server — Raccoon is sent"
	echo "over stdin, not installed. sudo checks are skipped (BatchMode has no sudo)."
}

# host -> filesystem-safe name for temp files.
_safe_name() {
	printf '%s' "$1" | tr '/:@ .' '______'
}

# Parse a fleet.conf line into HL_HOST / HL_PORT / HL_PROFILE. Returns 1 for
# blank/comment lines.
_parse_host_line() {
	local line="$1" hostport rest
	line="${line%%#*}"
	line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
	HL_HOST=""; HL_PORT=""; HL_PROFILE=""
	[[ -z "$line" ]] && return 1
	hostport="${line%%[[:space:]]*}"
	rest="${line#"$hostport"}"
	case "$rest" in
		*--profile*)
			HL_PROFILE="$(printf '%s' "$rest" | sed -n 's/.*--profile[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')"
			;;
	esac
	case "$hostport" in
		*:[0-9]*) HL_PORT="${hostport##*:}"; HL_HOST="${hostport%:*}" ;;
		*) HL_HOST="$hostport" ;;
	esac
	return 0
}

_read_hosts() {
	HOSTS=(); PORTS=(); PROFILES=()
	[[ -f "$HOSTS_FILE" ]] || return 0
	local line
	while IFS= read -r line || [[ -n "$line" ]]; do
		_parse_host_line "$line" || continue
		[[ -z "$HL_HOST" ]] && continue
		HOSTS+=("$HL_HOST")
		PORTS+=("$HL_PORT")
		PROFILES+=("$HL_PROFILE")
	done < "$HOSTS_FILE"
}

# Build the self-contained remote script: the libs inlined, then audit.sh with
# its source/SCRIPT_DIR lines neutralised. Lets the remote run with no install.
_remote_bundle() {
	cat "$SCRIPT_DIR/../lib/core/common.sh"
	echo
	cat "$SCRIPT_DIR/../lib/audit/checks.sh"
	echo
	cat "$SCRIPT_DIR/../lib/core/report.sh"
	echo
	sed -e '/^source .*lib\/core\/common\.sh/d' \
		-e '/^source .*lib\/audit\/checks\.sh/d' \
		-e '/^# shellcheck source=lib\/core\/report\.sh/d' \
		-e '/^source .*lib\/core\/report\.sh/d' \
		-e 's|^SCRIPT_PATH=.*|SCRIPT_PATH="/dev/null"|' \
		-e 's|^SCRIPT_DIR=.*|SCRIPT_DIR="/tmp"|' \
		"$SCRIPT_DIR/audit.sh"
}

# Run the remote audit for one host, writing its JSON to $out. A timer writes
# "$out.timeout" and kills ssh if FLEET_TIMEOUT is exceeded. Never fails the
# caller (errors become an unreachable/timeout marker at aggregation time).
run_host_audit() {
	local host="$1" port="$2" out="$3"
	local -a opts
	opts=(-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
	[[ -n "$port" ]] && opts+=(-p "$port")
	(
		"${RACCOON_SSH:-ssh}" "${opts[@]}" "$host" "bash -s -- --json --quiet" < "$BUNDLE_FILE" > "$out" 2>/dev/null &
		local ssh_pid=$!
		( sleep "$FLEET_TIMEOUT"; : > "$out.timeout"; kill "$ssh_pid" 2>/dev/null ) &
		local timer_pid=$!
		wait "$ssh_pid"
		local st=$?
		kill "$timer_pid" 2>/dev/null || true
		exit "$st"
	) 2>/dev/null || true
}

# Read each host's JSON, classify it, sum totals, and extract per-check results.
_aggregate() {
	FLEET_ROWS=()
	FLEET_REACHED=0; FLEET_UNREACHABLE=0
	FLEET_TOTAL_PASS=0; FLEET_TOTAL_WARN=0; FLEET_TOTAL_FAIL=0
	local i host safe out status pass warn fail
	for i in $(seq 0 $((${#HOSTS[@]} - 1))); do
		host="${HOSTS[$i]}"
		safe="$(_safe_name "$host")"
		out="$TMP_DIR/$safe.json"
		pass=0; warn=0; fail=0; status="unreachable"
		if [[ -f "$out.timeout" ]]; then
			status="timeout"
		elif [[ -s "$out" ]] && grep -q '"pass"' "$out"; then
			pass="$(grep -o '"pass": [0-9]*' "$out" | grep -o '[0-9]*' | head -1)"; pass="${pass:-0}"
			warn="$(grep -o '"warning": [0-9]*' "$out" | grep -o '[0-9]*' | head -1)"; warn="${warn:-0}"
			fail="$(grep -o '"fail": [0-9]*' "$out" | grep -o '[0-9]*' | head -1)"; fail="${fail:-0}"
			if [[ "$fail" -gt 0 || "$warn" -gt 0 ]]; then status="issues"; else status="ok"; fi
			FLEET_REACHED=$((FLEET_REACHED + 1))
			FLEET_TOTAL_PASS=$((FLEET_TOTAL_PASS + pass))
			FLEET_TOTAL_WARN=$((FLEET_TOTAL_WARN + warn))
			FLEET_TOTAL_FAIL=$((FLEET_TOTAL_FAIL + fail))
			grep -o '{"status": "[^"]*", "category": "[^"]*", "name": "[^"]*"[^}]*}' "$out" 2>/dev/null |
				sed -n 's/.*"status": "\([^"]*\)".*"name": "\([^"]*\)".*/\1	\2/p' > "$TMP_DIR/$safe.results" 2>/dev/null || true
		elif [[ -s "$out" ]]; then
			status="error"
		fi
		if [[ "$status" != "ok" && "$status" != "issues" ]]; then
			FLEET_UNREACHABLE=$((FLEET_UNREACHABLE + 1))
		fi
		FLEET_ROWS+=("$status"$'\t'"$host"$'\t'"$safe"$'\t'"$pass"$'\t'"$warn"$'\t'"$fail")
	done
}

_status_icon() {
	case "$1" in
		ok) printf '%s✓%s' "$GREEN" "$NC" ;;
		issues) printf '%s⚠%s' "$YELLOW" "$NC" ;;
		*) printf '%s✗%s' "$RED" "$NC" ;;
	esac
}

print_fleet_text() {
	local line
	line="$(printf '%*s' 48 '' | tr ' ' '─')"
	echo ""
	echo "┌${line}┐"
	printf '│ Fleet Audit — %-33s│\n' "$(date '+%Y-%m-%d %H:%M')"
	printf '│ %s host · %s connessioni parallele%*s│\n' "$FLEET_COUNT" "$PARALLEL" 12 ''
	echo "└${line}┘"
	echo ""

	local row status host safe pass warn fail label
	for row in ${FLEET_ROWS[@]+"${FLEET_ROWS[@]}"}; do
		IFS=$'\t' read -r status host safe pass warn fail <<< "$row"
		if [[ "$status" == "ok" || "$status" == "issues" ]]; then
			printf '  %s %-32s %3s pass  %2s warn  %2s fail\n' \
				"$(_status_icon "$status")" "$host" "$pass" "$warn" "$fail"
		else
			label="$(printf '%s' "$status" | tr '[:lower:]' '[:upper:]')"
			printf '  %s %-32s IRRAGGIUNGIBILE (%s)\n' "$(_status_icon "$status")" "$host" "$label"
		fi
	done

	echo ""
	echo "  ${line}"
	echo "  Totale: ${FLEET_REACHED}/${FLEET_COUNT} host raggiunti"
	echo "  Pass: ${FLEET_TOTAL_PASS}  Warning: ${FLEET_TOTAL_WARN}  Fail: ${FLEET_TOTAL_FAIL}"
	echo "  ${line}"

	# Hosts with failures -> actionable hint.
	for row in ${FLEET_ROWS[@]+"${FLEET_ROWS[@]}"}; do
		IFS=$'\t' read -r status host safe pass warn fail <<< "$row"
		if [[ "${fail:-0}" -gt 0 ]]; then
			echo ""
			echo "  Host con problemi: ${host} (${fail} fail)"
			echo "  Esegui: rcc fleet audit --host ${host} --explain"
			break
		fi
	done

	[[ "$EXPLAIN" == "true" ]] && _print_fleet_explain
	return 0
}

_print_fleet_explain() {
	local row status host safe pass warn fail rf st nm expl
	for row in ${FLEET_ROWS[@]+"${FLEET_ROWS[@]}"}; do
		IFS=$'\t' read -r status host safe pass warn fail <<< "$row"
		rf="$TMP_DIR/$safe.results"
		[[ -s "$rf" ]] || continue
		[[ "$status" == "ok" ]] && continue
		echo ""
		echo "  ${PURPLE_BOLD}${host}${NC}"
		while IFS=$'\t' read -r st nm; do
			[[ "$st" == "fail" || "$st" == "warn" ]] || continue
			expl="$(_check_explain "$nm")"
			[[ -n "$expl" ]] && echo "  ${GRAY}-> ${nm}: ${expl}${NC}"
		done < "$rf"
	done
}

print_fleet_json() {
	local row status host safe pass warn fail first=1
	echo "{"
	echo "  \"timestamp\": \"$(date -Iseconds)\","
	echo "  \"hosts\": ["
	for row in ${FLEET_ROWS[@]+"${FLEET_ROWS[@]}"}; do
		IFS=$'\t' read -r status host safe pass warn fail <<< "$row"
		if [[ $first -eq 1 ]]; then first=0; else echo "    ,"; fi
		echo "    {"
		echo "      \"host\": \"$host\","
		echo "      \"status\": \"$status\","
		echo "      \"pass\": $pass, \"warning\": $warn, \"fail\": $fail"
		echo "    }"
	done
	echo "  ],"
	echo "  \"summary\": {"
	echo "    \"total\": $FLEET_COUNT, \"reached\": $FLEET_REACHED, \"unreachable\": $FLEET_UNREACHABLE,"
	echo "    \"pass\": $FLEET_TOTAL_PASS, \"warning\": $FLEET_TOTAL_WARN, \"fail\": $FLEET_TOTAL_FAIL"
	echo "  }"
	echo "}"
}

_save_fleet_history() {
	mkdir -p "$FLEET_HISTORY"
	local ts file
	ts="$(date +%Y-%m-%d_%H:%M:%S)"
	file="$FLEET_HISTORY/fleet_${ts}.json"
	print_fleet_json > "$file" 2>/dev/null || true
	ln -sf "$file" "$FLEET_HISTORY/latest.json" 2>/dev/null || true
}

cmd_audit() {
	local single=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--hosts) if [[ $# -ge 2 ]]; then HOSTS_FILE="$2"; shift 2; else shift; fi ;;
			--parallel) if [[ $# -ge 2 ]]; then PARALLEL="$2"; shift 2; else shift; fi ;;
			--report) if [[ $# -ge 2 ]]; then REPORT_FILE="$2"; shift 2; else shift; fi ;;
			--host) if [[ $# -ge 2 ]]; then single="$2"; shift 2; else shift; fi ;;
			--json) OUTPUT_FORMAT="json"; shift ;;
			--explain) EXPLAIN=true; shift ;;
			--profile) shift; [[ $# -gt 0 && "$1" != -* ]] && shift ;;
			*) shift ;;
		esac
	done

	if [[ -n "$single" ]]; then
		_parse_host_line "$single" || true
		HOSTS=("$HL_HOST"); PORTS=("$HL_PORT"); PROFILES=("$HL_PROFILE")
	else
		_read_hosts
	fi
	FLEET_COUNT=${#HOSTS[@]}

	if [[ "$FLEET_COUNT" -eq 0 ]]; then
		echo "Nessun host configurato. Aggiungi con: rcc fleet add <host>"
		return 0
	fi

	TMP_DIR="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '$TMP_DIR'" EXIT
	BUNDLE_FILE="$TMP_DIR/bundle.sh"
	_remote_bundle > "$BUNDLE_FILE"
	FLEET_RESULTS_DIR="$TMP_DIR"

	local pids=() i host port safe
	for i in $(seq 0 $((FLEET_COUNT - 1))); do
		host="${HOSTS[$i]}"; port="${PORTS[$i]}"; safe="$(_safe_name "$host")"
		run_host_audit "$host" "$port" "$TMP_DIR/$safe.json" &
		pids+=($!)
		if [[ ${#pids[@]} -ge $PARALLEL ]]; then
			wait "${pids[0]}" 2>/dev/null || true
			pids=("${pids[@]:1}")
		fi
	done
	wait 2>/dev/null || true

	_aggregate

	if [[ "$OUTPUT_FORMAT" == "json" ]]; then
		print_fleet_json
	else
		if [[ -n "$REPORT_FILE" ]]; then
			REPORT_DATE="$(date '+%Y-%m-%d %H:%M')"
			case "$REPORT_FILE" in
				*.rtf) render_fleet_rtf > "$REPORT_FILE" ;;
				*) render_fleet_md > "$REPORT_FILE" ;;
			esac
			echo "  Report saved to: $REPORT_FILE"
		fi
		print_fleet_text
	fi

	_save_fleet_history
}

cmd_status() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--hosts) if [[ $# -ge 2 ]]; then HOSTS_FILE="$2"; shift 2; else shift; fi ;;
			*) shift ;;
		esac
	done
	_read_hosts
	if [[ ${#HOSTS[@]} -eq 0 ]]; then
		echo "Nessun host configurato."
		return 0
	fi
	local i host port
	for i in $(seq 0 $((${#HOSTS[@]} - 1))); do
		host="${HOSTS[$i]}"; port="${PORTS[$i]}"
		local -a opts
		opts=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
		[[ -n "$port" ]] && opts+=(-p "$port")
		if "${RACCOON_SSH:-ssh}" "${opts[@]}" "$host" "echo ok" 2>/dev/null | grep -q ok; then
			echo "  ${GREEN}✓${NC} $host"
		else
			echo "  ${RED}✗${NC} $host"
		fi
	done
}

cmd_add() {
	local host="${1:-}"
	if [[ -z "$host" ]]; then
		echo "Uso: rcc fleet add <host>"
		return 0
	fi
	mkdir -p "$(dirname "$FLEET_CONF")"
	touch "$FLEET_CONF"
	if grep -qxF "$host" "$FLEET_CONF" 2>/dev/null; then
		echo "Host già presente: $host"
		return 0
	fi
	echo "$host" >> "$FLEET_CONF"
	echo "Aggiunto: $host"
	echo "Verifica connessione con: rcc fleet status"
}

cmd_remove() {
	local host="${1:-}"
	if [[ -z "$host" ]]; then
		echo "Uso: rcc fleet remove <host>"
		return 0
	fi
	if [[ ! -f "$FLEET_CONF" ]] || ! grep -qF "$host" "$FLEET_CONF"; then
		echo "Host non trovato: $host"
		return 0
	fi
	if [[ -t 0 ]]; then
		local answer
		printf "Rimuovere '%s'? [y/N] " "$host"
		read -r answer || answer="n"
		[[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Annullato."; return 0; }
	fi
	grep -vF "$host" "$FLEET_CONF" > "$FLEET_CONF.tmp" 2>/dev/null || true
	mv "$FLEET_CONF.tmp" "$FLEET_CONF"
	echo "Rimosso: $host"
}

cmd_list() {
	_read_hosts
	if [[ ${#HOSTS[@]} -eq 0 ]]; then
		echo "Nessun host configurato."
		return 0
	fi
	local i host profile
	for i in $(seq 0 $((${#HOSTS[@]} - 1))); do
		host="${HOSTS[$i]}"; profile="${PROFILES[$i]}"
		if [[ -n "$profile" ]]; then
			echo "  $((i + 1)). $host (profilo: $profile)"
		else
			echo "  $((i + 1)). $host"
		fi
	done
}

main() {
	local sub="${1:-audit}"
	[[ $# -gt 0 ]] && shift
	case "$sub" in
		audit) cmd_audit "$@" ;;
		status) cmd_status "$@" ;;
		add) cmd_add "$@" ;;
		remove) cmd_remove "$@" ;;
		list) cmd_list "$@" ;;
		help | --help | -h) show_fleet_help ;;
		*) show_fleet_help ;;
	esac
}

main "$@"
