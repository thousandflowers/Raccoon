#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_ports_help() {
	print_help_header "ports" "List open TCP/UDP ports with process information" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_ports_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		echo "Unknown option: $arg"
		echo "Usage: rcc ports [--json]"
		exit 1
		;;
	esac
done

# _ports_awk: the one reading of lsof, shared by both output paths so they can
# never disagree about which port a row is on — they used to, and both were
# wrong: the JSON took the last colon-field of NAME, which on a connected
# socket is the *peer's* port, and the table took the first `:digits` match,
# which inside an IPv6 address is a hextet.
#
# It reads two inputs: `ps -axo pid=,comm=` first, then lsof. The ps pass costs
# one process for the whole run, not one per row, and it is what makes the
# process name usable: lsof truncates COMMAND to nine characters and sometimes
# reports something else entirely (a build number, for one Electron app).
#
# mode=json prints the array; mode=text prints a sort key then tab-separated
# port, proto, pid, user, process, address, state.
_ports_awk() {
	awk -v mode="$1" '
	function jesc(s) {
		gsub(/\\/, "\\\\", s)   # backslash first, or it would escape the others
		gsub(/"/, "\\\"", s)
		gsub(/\t/, "\\t", s)
		gsub(/\r/, "\\r", s)
		gsub(/\n/, "\\n", s)
		return s
	}
	# lsof writes a space in a command name as \x20. That is its transport
	# encoding, not part of the name, so it is decoded here; anything else it
	# escapes survives as a literal backslash sequence and jesc keeps it valid.
	function unescape(s) {
		gsub(/\\x20/, " ", s)
		sub(/[ \t]+$/, "", s)
		return s
	}
	# The local port is what follows the last colon on the near side of "->".
	# In [fe80::1]:56122 that colon is the one after the closing bracket, so
	# scanning from the right needs no special case for IPv6.
	#
	# THIS RULE IS WRITTEN TWICE. The other copy is rcc_local_port in
	# lib/core/common.sh, which bin/network.sh calls per line; it lives there
	# because this one reads the whole table in a single awk pass and would lose
	# that by handing every row back to the shell. Change one and you must change
	# the other; the two are held together by tests/test_port_equivalence.bats,
	# which lifts this function straight out of this file and compares it against
	# the bash copy on the same inputs.
	function local_port(addr,   i) {
		for (i = length(addr); i > 0; i--)
			if (substr(addr, i, 1) == ":") return substr(addr, i + 1)
		return ""
	}
	BEGIN { first = 1; if (mode == "json") printf "[" }
	FNR == NR {
		if ($1 !~ /^[0-9]+$/) next
		pid = $1
		path = $0
		sub(/^[ \t]*[0-9]+[ \t]+/, "", path)
		sub(/^.*\//, "", path)
		if (path != "") resolved[pid] = path
		next
	}
	$1 == "COMMAND" && $2 == "PID" { next }
	{
		cmd = $1; pid = $2; user = $3; proto = $8; name = $9; state = $10
		if (pid !~ /^[0-9]+$/) next
		if (proto != "TCP" && proto != "UDP") next

		arrow = index(name, "->")
		address = (arrow > 0) ? substr(name, 1, arrow - 1) : name
		port = local_port(address)
		if (port == "" || address == "") next

		gsub(/[()]/, "", state)
		cmd = (pid in resolved) ? resolved[pid] : unescape(cmd)
		user = unescape(user)

		key = port SUBSEP proto SUBSEP pid SUBSEP address SUBSEP state
		if (key in seen) next
		seen[key] = 1

		if (mode == "json") {
			if (first) first = 0; else printf ","
			printf "\n    {\"port\": \"%s\", \"proto\": \"%s\", \"pid\": %s, \"user\": \"%s\", \"process\": \"%s\", \"address\": \"%s\", \"state\": \"%s\"}",
				jesc(port), jesc(proto), pid, jesc(user), jesc(cmd), jesc(address), jesc(state)
		} else {
			# The leading key is for sort only and is cut off again: an unbound
			# socket has "*" for a port and would otherwise sort as zero, putting
			# it above port 1.
			printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
				(port ~ /^[0-9]+$/ ? port : 99999999), port, proto, pid, user, cmd, address, state
		}
	}
	END { if (mode == "json") print (first ? "]" : "\n  ]") }
	' "$2" -
}

_ports_rows() {
	local mode="$1" data psmap
	data=$(lsof -iTCP -iUDP -nP 2>/dev/null || true)

	if [[ -z "$data" ]]; then
		[[ "$mode" == "json" ]] && echo "[]"
		return 0
	fi

	# One ps for the whole listing. A failure here only means the names stay as
	# lsof reported them.
	# The marker line keeps this file non-empty. awk tells the two inputs apart
	# with FNR == NR, which silently reads the second file as the first when the
	# first is empty — and ps failing, or being stubbed out, is exactly that case.
	psmap=$(mktemp "${TMPDIR:-/tmp}/rcc-ports-ps.XXXXXX")
	echo "# rcc pid map" > "$psmap"
	ps -axo pid=,comm= >> "$psmap" 2>/dev/null || true

	printf '%s\n' "$data" | _ports_awk "$mode" "$psmap"

	rm -f "$psmap"
}

display_ports_json() {
	_ports_rows json
}

main() {
	if [[ "$JSON_OUTPUT" == "true" ]]; then
		display_ports_json
		exit 0
	fi

	print_section_header "Network Ports"

	local rows
	# No -u here. The rows are already unique — awk keyed them on the whole
	# socket — and `sort -u` with restricted keys drops every row that merely
	# ties on those keys, which is how the old table showed three sockets out
	# of a hundred and fifty.
	rows=$(_ports_rows text | sort -t $'\t' -k1,1n -k6,6 | cut -f2-)

	if [[ -z "$rows" ]]; then
		print_info "No ports found"
		echo ""
		print_success "Completed"
		return 0
	fi

	print_table_header "PORT|PROTO|PID|PROCESS|STATE|ADDRESS" 8 6 7 20 12 24

	# user is read into _ : it is in the JSON, but a column for it would push
	# the table past the width of the terminal for a value that is almost always
	# the same one.
	local port proto pid cmd address state
	while IFS=$'\t' read -r port proto pid _ cmd address state; do
		[[ -n "$port" ]] || continue
		# Values are cut to their column: resolving names off the PID makes them
		# real names, and a real name can be longer than the column is wide.
		cmd="${cmd:0:20}"
		address="${address:0:24}"
		if [[ "$port" =~ ^[0-9]+$ ]] && ((port < 1024)); then
			print_table_row "${YELLOW}${port}${NC}|$proto|$pid|$cmd|${state:-}|$address" 8 6 7 20 12 24
		else
			print_table_row "$port|$proto|$pid|$cmd|${state:-}|$address" 8 6 7 20 12 24
		fi
	done <<< "$rows"

	echo ""
	print_success "Completed"
}

main "$@"
