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
FLEET_GROUPS="$HOME/.raccoon/fleet-groups.conf"
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
	echo "  scan             Discover Macs on the LAN and show fleet-readiness"
	echo "  group <cmd>      Manage host groups (add/remove/list)"
	echo "  run [opts] -- C  Run command C over SSH on every host (or a group)"
	echo "  add <host>       Add a host to fleet.conf"
	echo "  remove <host>    Remove a host from fleet.conf"
	echo "  list             List configured hosts"
	echo ""
	echo "Options (scan):"
	echo "  --user U         SSH user to probe with (default: \$USER)"
	echo "  --subnet BASE    Override subnet base, e.g. 192.168.1 (default: auto)"
	echo "  --timeout N      Per-host SSH timeout in seconds (default: 5)"
	echo "  --add            Add every ready host to fleet.conf (no prompt)"
	echo "  --json           Output structured JSON"
	echo "  (env) SCAN_MAX   Hard wall-clock budget for the whole scan (default: 45s)"
	echo ""
	echo "Groups:"
	echo "  rcc fleet group add office mario@192.168.1.10 luca@192.168.1.11"
	echo "  rcc fleet group list [name]      rcc fleet group remove office [host]"
	echo "  rcc fleet audit --group office   rcc fleet run --group office -- softwareupdate -l"
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
		# Reap ssh and cancel the timer with fd2 redirected only around the `wait`
		# builtins, so the shell's "Terminated: 15" job message is swallowed while
		# ssh's own stdout/stderr (already flowing to the caller) is preserved.
		local st=0
		{ wait "$ssh_pid"; st=$?; } 2>/dev/null
		{ kill "$timer_pid" 2>/dev/null; wait "$timer_pid"; } 2>/dev/null || true
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
			pass="$(grep -o '"pass": [0-9]*' "$out" | grep -o '[0-9]*' | head -1 || true)"; pass="${pass:-0}"
			warn="$(grep -o '"warning": [0-9]*' "$out" | grep -o '[0-9]*' | head -1 || true)"; warn="${warn:-0}"
			fail="$(grep -o '"fail": [0-9]*' "$out" | grep -o '[0-9]*' | head -1 || true)"; fail="${fail:-0}"
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
	printf '│ %s hosts · %s parallel connections%*s│\n' "$FLEET_COUNT" "$PARALLEL" 12 ''
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
			printf '  %s %-32s UNREACHABLE (%s)\n' "$(_status_icon "$status")" "$host" "$label"
		fi
	done

	echo ""
	echo "  ${line}"
	echo "  Total: ${FLEET_REACHED}/${FLEET_COUNT} hosts reached"
	echo "  Pass: ${FLEET_TOTAL_PASS}  Warning: ${FLEET_TOTAL_WARN}  Fail: ${FLEET_TOTAL_FAIL}"
	echo "  ${line}"

	# Hosts with failures -> actionable hint.
	for row in ${FLEET_ROWS[@]+"${FLEET_ROWS[@]}"}; do
		IFS=$'\t' read -r status host safe pass warn fail <<< "$row"
		if [[ "${fail:-0}" -gt 0 ]]; then
			echo ""
			echo "  Host with issues: ${host} (${fail} fail)"
			echo "  Run: rcc fleet audit --host ${host} --explain"
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
	local single="" group=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--hosts) if [[ $# -ge 2 ]]; then HOSTS_FILE="$2"; shift 2; else shift; fi ;;
			--group) if [[ $# -ge 2 ]]; then group="$2"; shift 2; else shift; fi ;;
			--parallel) if [[ $# -ge 2 ]]; then PARALLEL="$2"; shift 2; else shift; fi ;;
			--report) if [[ $# -ge 2 ]]; then REPORT_FILE="$2"; shift 2; else shift; fi ;;
			--host) if [[ $# -ge 2 ]]; then single="$2"; shift 2; else shift; fi ;;
			--json) OUTPUT_FORMAT="json"; shift ;;
			--explain) EXPLAIN=true; shift ;;
			--profile) shift; [[ $# -gt 0 && "$1" != -* ]] && shift ;;
			*) shift ;;
		esac
	done

	if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -eq 0 ]]; then
		PARALLEL=5
	fi

	if [[ -n "$single" ]]; then
		_parse_host_line "$single" || true
		HOSTS=("$HL_HOST"); PORTS=("$HL_PORT"); PROFILES=("$HL_PROFILE")
	elif [[ -n "$group" ]]; then
		_load_group "$group"
	else
		_read_hosts
	fi
	FLEET_COUNT=${#HOSTS[@]}

	if [[ "$FLEET_COUNT" -eq 0 ]]; then
		echo "No hosts configured. Add one with: rcc fleet add <host>"
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

	# Semantic exit code mirrors `rcc audit`: 1 if any host has a failure, 2 if
	# only warnings (or unreachable hosts), 0 if every reached host is clean. Lets
	# CI gate on a whole-fleet sweep.
	if [[ "${FLEET_TOTAL_FAIL:-0}" -gt 0 ]]; then
		return 1
	elif [[ "${FLEET_TOTAL_WARN:-0}" -gt 0 || "${FLEET_UNREACHABLE:-0}" -gt 0 ]]; then
		return 2
	fi
	return 0
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
		echo "No hosts configured."
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
		echo "Usage: rcc fleet add <host>"
		return 0
	fi
	mkdir -p "$(dirname "$FLEET_CONF")"
	touch "$FLEET_CONF"
	if grep -qxF "$host" "$FLEET_CONF" 2>/dev/null; then
		echo "Host already present: $host"
		return 0
	fi
	echo "$host" >> "$FLEET_CONF"
	echo "Added: $host"
	echo "Verify the connection with: rcc fleet status"
}

cmd_remove() {
	local host="${1:-}"
	if [[ -z "$host" ]]; then
		echo "Usage: rcc fleet remove <host>"
		return 0
	fi
	if [[ ! -f "$FLEET_CONF" ]] || ! grep -qxF "$host" "$FLEET_CONF"; then
		echo "Host not found: $host"
		return 0
	fi
	if [[ -t 0 ]]; then
		local answer
		printf "Remove '%s'? [y/N] " "$host"
		read -r answer || answer="n"
		[[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Cancelled."; return 0; }
	fi
	grep -vxF "$host" "$FLEET_CONF" > "$FLEET_CONF.tmp" 2>/dev/null || true
	mv "$FLEET_CONF.tmp" "$FLEET_CONF"
	echo "Removed: $host"
}

cmd_list() {
	_read_hosts
	if [[ ${#HOSTS[@]} -eq 0 ]]; then
		echo "No hosts configured."
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

# --- groups: name sets of already-added hosts, then act on them in bulk -------
# Storage: one membership per line, "group<TAB>host" (host = the fleet.conf
# string, e.g. mario@192.168.1.10). Plain text, grep/awk-friendly.

_group_members() {
	[[ -f "$FLEET_GROUPS" ]] || return 0
	awk -F'\t' -v g="$1" 'NF>=2 && $1==g {print $2}' "$FLEET_GROUPS"
}

_group_names() {
	[[ -f "$FLEET_GROUPS" ]] || return 0
	awk -F'\t' 'NF>=2 {print $1}' "$FLEET_GROUPS" | sort -u
}

# Load a group's members into HOSTS/PORTS/PROFILES (same shape as _read_hosts).
_load_group() {
	HOSTS=(); PORTS=(); PROFILES=()
	local m
	while IFS= read -r m; do
		[[ -z "$m" ]] && continue
		_parse_host_line "$m" || continue
		[[ -z "$HL_HOST" ]] && continue
		HOSTS+=("$HL_HOST"); PORTS+=("$HL_PORT"); PROFILES+=("$HL_PROFILE")
	done < <(_group_members "$1")
}

cmd_group() {
	local action="${1:-list}"
	[[ $# -gt 0 ]] && shift
	mkdir -p "$(dirname "$FLEET_GROUPS")"
	case "$action" in
		add)
			local name="${1:-}"
			[[ $# -gt 0 ]] && shift
			if [[ -z "$name" || $# -eq 0 ]]; then
				echo "Uso: rcc fleet group add <nome> <host...>"; return 1
			fi
			local h
			for h in "$@"; do
				if [[ -f "$HOSTS_FILE" ]] && ! grep -qF "$h" "$HOSTS_FILE" 2>/dev/null; then
					echo "  ${YELLOW}warning${NC}: $h is not in fleet.conf (add it with: rcc fleet add $h)"
				fi
				if grep -qxF "$name	$h" "$FLEET_GROUPS" 2>/dev/null; then
					echo "  already in $name: $h"
				else
					printf '%s\t%s\n' "$name" "$h" >> "$FLEET_GROUPS"
					echo "  ${GREEN}+${NC} $name: $h"
				fi
			done
			;;
		remove | rm)
			local name="${1:-}"
			[[ $# -gt 0 ]] && shift
			[[ -z "$name" ]] && { echo "Uso: rcc fleet group remove <nome> [host...]"; return 1; }
			[[ -f "$FLEET_GROUPS" ]] || { echo "No groups."; return 0; }
			local tmp; tmp="$(mktemp)"
			if [[ $# -eq 0 ]]; then
				awk -F'\t' -v g="$name" '$1!=g' "$FLEET_GROUPS" > "$tmp" && mv "$tmp" "$FLEET_GROUPS"
				echo "Group removed: $name"
			else
				cp "$FLEET_GROUPS" "$tmp"
				local h
				for h in "$@"; do
					awk -F'\t' -v g="$name" -v hh="$h" '!($1==g && $2==hh)' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
				done
				mv "$tmp" "$FLEET_GROUPS"
				echo "Removed from $name: $*"
			fi
			;;
		list | ls)
			if [[ -n "${1:-}" ]]; then
				echo "Group ${1}:"
				_group_members "$1" | awk 'NF' | sed 's/^/  /'
			else
				local names g count
				names="$(_group_names)"
				if [[ -z "$names" ]]; then
					echo "No groups. Create one with: rcc fleet group add <name> <host...>"
					return 0
				fi
				while IFS= read -r g; do
					[[ -z "$g" ]] && continue
					count="$(_group_members "$g" | awk 'NF' | wc -l | tr -d ' ')"
					printf '  %-20s %s %s\n' "$g" "$count" "$([[ "$count" -eq 1 ]] && echo host || echo hosts)"
				done <<< "$names"
			fi
			;;
		*)
			echo "Uso: rcc fleet group <add|remove|list> ..."; return 1
			;;
	esac
}

# Run one SSH command, key auth only. Output (stdout+stderr) goes to the caller.
_run_one() {
	local host="$1" port="$2" cmd="$3"
	local -a opts=(-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
	[[ -n "$port" ]] && opts+=(-p "$port")
	# Overall wall-clock bound (mirrors run_host_audit): a timer kills ssh if it
	# runs past FLEET_TIMEOUT so a hung remote command can't block wait forever.
	(
		"${RACCOON_SSH:-ssh}" "${opts[@]}" "$host" "$cmd" &
		local ssh_pid=$!
		( sleep "$FLEET_TIMEOUT"; kill "$ssh_pid" 2>/dev/null ) &
		local timer_pid=$!
		# Reap ssh and cancel the timer with fd2 redirected only around the `wait`
		# builtins, so the shell's "Terminated: 15" job message is swallowed while
		# ssh's own stdout/stderr (already flowing to the caller) is preserved.
		local st=0
		{ wait "$ssh_pid"; st=$?; } 2>/dev/null
		{ kill "$timer_pid" 2>/dev/null; wait "$timer_pid"; } 2>/dev/null || true
		exit "$st"
	) || true
}

# run [--group N] [--parallel N] -- <command>   (no group = every host)
cmd_run() {
	local group="" parallel="$PARALLEL"
	local -a rest=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--group) if [[ $# -ge 2 ]]; then group="$2"; shift 2; else shift; fi ;;
			--parallel) if [[ $# -ge 2 ]]; then parallel="$2"; shift 2; else shift; fi ;;
			--) shift; rest+=("$@"); break ;;
			*) rest+=("$1"); shift ;;
		esac
	done
	if ! [[ "$parallel" =~ ^[0-9]+$ ]] || [[ "$parallel" -eq 0 ]]; then
		parallel="$PARALLEL"
	fi
	local cmd=""
	[[ ${#rest[@]} -gt 0 ]] && cmd="$(printf '%q ' "${rest[@]}")"
	if [[ -z "$cmd" ]]; then
		echo "Usage: rcc fleet run [--group <name>] -- <command>"; return 1
	fi

	if [[ -n "$group" ]]; then _load_group "$group"; else _read_hosts; fi
	if [[ ${#HOSTS[@]} -eq 0 ]]; then
		echo "No hosts${group:+ in group $group}. Add one with: rcc fleet add <host>"
		return 0
	fi

	local tmp; tmp="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" EXIT
	local i host port safe
	for i in $(seq 0 $((${#HOSTS[@]} - 1))); do
		host="${HOSTS[$i]}"; port="${PORTS[$i]}"; safe="$(_safe_name "$host")"
		( _run_one "$host" "$port" "$cmd" > "$tmp/$safe" 2>&1 ) &
		(( (i + 1) % parallel == 0 )) && wait
	done
	wait

	for i in $(seq 0 $((${#HOSTS[@]} - 1))); do
		host="${HOSTS[$i]}"; safe="$(_safe_name "$host")"
		echo "${PURPLE_BOLD}=== ${host} ===${NC}"
		cat "$tmp/$safe" 2>/dev/null || true
		echo ""
	done
	rm -rf "$tmp"
}

# --- scan: discover Macs on the LAN and classify their fleet-readiness --------

# Resolve the active interface's /24 base (e.g. "192.168.1") or "" if offline.
_scan_subnet_base() {
	local iface ip
	iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
	[[ -z "$iface" ]] && iface=en0
	ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
	[[ -z "$ip" ]] && return 0
	printf '%s' "${ip%.*}"
}

# Ping-sweep the /24 (best-effort, populates the ARP cache) then read live IPs.
_scan_pingsweep() {
	local base="$1" h
	[[ -z "$base" ]] && return 0
	for h in $(seq 1 254); do
		ping -c 1 -W 300 "$base.$h" >/dev/null 2>&1 &
	done
	wait
	arp -an 2>/dev/null | awk -v b="$base." '
		index($2, "(") { ip = $2; gsub(/[()]/, "", ip);
			if (index(ip, b) == 1 && $4 != "(incomplete)" && $4 != "incomplete") print ip }'
}

# Bonjour: hosts advertising _ssh._tcp, resolved to their .local name (ssh
# reaches *.local via mDNS, no IP needed). Best-effort; needs dns-sd.
# ponytail: ping-sweep is the backbone; this only adds mDNS-only / nice-named hosts.
_scan_bonjour() {
	command -v dns-sd >/dev/null 2>&1 || return 0
	local browse insts inst n=0 btmp
	browse="$( { dns-sd -B _ssh._tcp local. & local p=$!; sleep 2; kill "$p" 2>/dev/null || true; } 2>/dev/null )"
	# Cap advertisers so the resolve step can't blow past the budget on a busy LAN.
	insts="$(printf '%s\n' "$browse" |
		awk '/Add/ { for (i=7;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"\n") }' |
		awk 'NF' | sort -u | head -n "${SCAN_BONJOUR_MAX:-32}")"
	[[ -z "$insts" ]] && return 0
	# Resolve every advertiser in parallel (was sequential N×sleep) into a temp
	# dir, then a single wait — the whole resolve step is ~one sleep, not N.
	btmp="$(mktemp -d)"
	while IFS= read -r inst; do
		[[ -z "$inst" ]] && continue
		n=$((n + 1))
		(
			lookup="$( { dns-sd -L "$inst" _ssh._tcp local. & lp=$!; sleep 1; kill "$lp" 2>/dev/null || true; } 2>/dev/null )"
			target="$(printf '%s\n' "$lookup" | sed -n 's/.* \([^ ]*\.local\)\.\{0,1\}:[0-9].*/\1/p' | head -1)"
			[[ -n "$target" ]] && printf '%s\n' "$target" > "$btmp/$n"
		) &
	done <<< "$insts"
	wait
	cat "$btmp"/* 2>/dev/null | awk 'NF' | sort -u
	rm -rf "$btmp"
}

# Classify one host: ready | setup | non-mac | down.
#   down    = no SSH (port 22 closed)            ready   = Darwin + key auth OK
#   setup   = SSH up but key auth not configured  non-mac = reachable but not macOS
_scan_probe() {
	local host="$1" user="$2" timeout="$3" out rc
	if [[ -z "${RACCOON_SCAN_HOSTS:-}" ]]; then
		nc -z -G 2 -w 2 "$host" 22 >/dev/null 2>&1 || { echo down; return; }
	fi
	# Guard the substitution: under `set -e`, a failed ssh in `out="$(...)"` aborts
	# the function before `echo setup`, silently dropping every host that needs
	# `ssh-copy-id` — which is exactly scan's whole point.
	# ConnectTimeout only bounds the TCP connect; a server that accepts the socket
	# then stalls the handshake (e.g. a multi-homed .local self-probe) would hang
	# forever. A timer kills ssh past $timeout so every probe is wall-clock bound.
	if out="$(
		"${RACCOON_SSH:-ssh}" -o BatchMode=yes -o ConnectTimeout="$timeout" \
			-o StrictHostKeyChecking=accept-new "$user@$host" "uname -s" 2>/dev/null &
		_sp=$!
		( sleep "$timeout"; kill "$_sp" 2>/dev/null ) >/dev/null 2>&1 &
		_wp=$!
		wait "$_sp"; _st=$?
		kill "$_wp" 2>/dev/null || true
		exit "$_st"
	)"; then
		rc=0
	else
		rc=$?
	fi
	if [[ $rc -eq 0 ]]; then
		[[ "$out" == "Darwin" ]] && echo ready || echo non-mac
	else
		echo setup
	fi
}

cmd_scan() {
	local user="${USER:-root}" subnet="" timeout=5 add_mode="" fmt="text"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--user) if [[ $# -ge 2 ]]; then user="$2"; shift 2; else shift; fi ;;
			--subnet) if [[ $# -ge 2 ]]; then subnet="$2"; shift 2; else shift; fi ;;
			--timeout) if [[ $# -ge 2 ]]; then timeout="$2"; shift 2; else shift; fi ;;
			--add) add_mode=1; shift ;;
			--json) fmt="json"; shift ;;
			*) shift ;;
		esac
	done

	local candidates
	if [[ -n "${RACCOON_SCAN_HOSTS:-}" ]]; then
		# shellcheck disable=SC2086  # intentional word-split: space/newline host list
		candidates="$(printf '%s\n' ${RACCOON_SCAN_HOSTS})"
	else
		[[ "$fmt" == "text" ]] && echo "Scanning network..." >&2
		candidates="$( { _scan_pingsweep "${subnet:-$(_scan_subnet_base)}"; _scan_bonjour; } )"
	fi
	candidates="$(printf '%s\n' "$candidates" | awk 'NF' | sort -u)"
	if [[ -z "$candidates" ]]; then
		echo "No hosts found on the network."
		return 0
	fi

	local tmp; tmp="$(mktemp -d)"
	local host safe count guard _p
	count="$(printf '%s\n' "$candidates" | grep -c . || true)"
	[[ "$fmt" == "text" ]] && echo "Probing ${count} host(s) (budget ${SCAN_MAX:-45}s)..." >&2
	# Launch every probe concurrently — each _scan_probe is self-bounded by nc -w
	# and the ssh timer, so the whole phase is ~one host's timeout. Each writes
	# its result file as it finishes, so a watchdog deadline still yields output.
	local -a ppids=()
	while IFS= read -r host; do
		[[ -z "$host" ]] && continue
		safe="$(_safe_name "$host")"
		( printf '%s\t%s\n' "$(_scan_probe "$host" "$user" "$timeout")" "$host" > "$tmp/$safe" ) &
		ppids+=($!)
	done <<< "$candidates"
	# Hard overall backstop: kill any probe still alive past SCAN_MAX so the scan
	# can never hang regardless of network pathologies (e.g. ssh that connects
	# then stalls the handshake). Whatever finished is still collected below.
	( sleep "${SCAN_MAX:-45}"
	  for _p in ${ppids[@]+"${ppids[@]}"}; do kill "$_p" 2>/dev/null; pkill -P "$_p" 2>/dev/null; done
	) >/dev/null 2>&1 &
	guard=$!
	for _p in ${ppids[@]+"${ppids[@]}"}; do wait "$_p" 2>/dev/null || true; done
	# Cancel the backstop (and its sleep child) WITHOUT leaking a job-control
	# "Terminated: 15" line onto stderr — that line would corrupt --json output
	# and prepend to bats' merged $output. `wait` inside the stderr-redirected
	# block swallows the shell's async-job termination report.
	{ pkill -P "$guard" 2>/dev/null; kill "$guard" 2>/dev/null; wait "$guard"; } 2>/dev/null || true

	# Collect rows; build the list of ready user@host targets.
	local rows="" ready_list="" state rhost f
	for f in "$tmp"/*; do
		[[ -f "$f" ]] || continue
		IFS=$'\t' read -r state rhost < "$f"
		[[ -z "$state" ]] && continue
		rows+="$state	$rhost"$'\n'
		[[ "$state" == "ready" ]] && ready_list+="$user@$rhost"$'\n'
	done
	rm -rf "$tmp"

	if [[ "$fmt" == "json" ]]; then
		_scan_print_json "$rows"
		return 0
	fi

	_scan_print_text "$rows"

	local ready_count
	ready_count="$(printf '%s' "$ready_list" | awk 'NF' | wc -l | tr -d ' ')"
	[[ "$ready_count" -eq 0 ]] && return 0

	if [[ -n "$add_mode" ]]; then
		printf '%s\n' "$ready_list" | awk 'NF' | while IFS= read -r h; do cmd_add "$h"; done
		return 0
	fi

	local answer="n"
	if [[ -t 0 ]]; then
		printf "Add %s ready host(s) to fleet.conf? [y/N] " "$ready_count"
		read -r answer || answer="n"
	fi
	if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
		printf '%s\n' "$ready_list" | awk 'NF' | while IFS= read -r h; do cmd_add "$h"; done
	else
		echo "Not added. To add manually:"
		printf '%s\n' "$ready_list" | awk 'NF' | while IFS= read -r h; do echo "  rcc fleet add $h"; done
	fi
}

_scan_state_label() {
	case "$1" in
		ready)   printf '%s✓ ready%s        ' "$GREEN" "$NC" ;;
		setup)   printf '%s⚠ setup needed%s ' "$YELLOW" "$NC" ;;
		non-mac) printf '%s✗ non-Mac%s      ' "$GRAY" "$NC" ;;
		*)       printf '%s✗ %s%s          ' "$GRAY" "$1" "$NC" ;;
	esac
}

_scan_print_text() {
	local rows="$1" state host nready=0 nsetup=0 nother=0
	print_section_header "Fleet Scan"
	while IFS=$'\t' read -r state host; do
		[[ -z "$state" || "$state" == "down" ]] && continue
		printf '  %s %s\n' "$(_scan_state_label "$state")" "$host"
		[[ "$state" == "setup" ]] && echo "      ${GRAY}→ ssh-copy-id $host${NC}"
		case "$state" in ready) nready=$((nready+1));; setup) nsetup=$((nsetup+1));; non-mac) nother=$((nother+1));; esac
	done <<< "$rows"
	echo ""
	echo "  ${GRAY}ready: ${nready}  setup needed: ${nsetup}  non-Mac: ${nother}${NC}"
}

_scan_print_json() {
	local rows="$1" state host first=1
	echo "{"
	echo "  \"timestamp\": \"$(date -Iseconds)\","
	echo "  \"hosts\": ["
	while IFS=$'\t' read -r state host; do
		[[ -z "$state" || "$state" == "down" ]] && continue
		if [[ $first -eq 1 ]]; then first=0; else echo "    ,"; fi
		printf '    {"host": "%s", "state": "%s"}\n' "$host" "$state"
	done <<< "$rows"
	echo "  ]"
	echo "}"
}

main() {
	local sub="${1:-audit}"
	[[ $# -gt 0 ]] && shift
	case "$sub" in
		audit) cmd_audit "$@" ;;
		status) cmd_status "$@" ;;
		scan) cmd_scan "$@" ;;
		group) cmd_group "$@" ;;
		run) cmd_run "$@" ;;
		add) cmd_add "$@" ;;
		remove) cmd_remove "$@" ;;
		list) cmd_list "$@" ;;
		help | --help | -h) show_fleet_help ;;
		*) show_fleet_help; return 1 ;;
	esac
}

main "$@"
