load test_helper

# The rule for reading a local port out of an lsof NAME field is written twice:
# in bash as rcc_local_port (lib/core/common.sh) and in awk as local_port
# (bin/ports.sh). That is deliberate — ports.sh reads a hundred and fifty rows
# in one awk pass, and handing the raw NAME back to a shell function per row
# costs more than the duplication does — but two copies of a rule drift, and
# this one has already been wrong twice, in two different ways.
#
# This file is the price of keeping them apart: the same inputs go into both,
# and both have to answer the same thing.

setup() {
	setup_raccoon_env
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/lib/core/common.sh"
	FAILURES=""
}
teardown() { teardown_raccoon_env; }

# Drive the awk copy through the source of bin/ports.sh itself: the function and
# the two lines that split on "->" are lifted out verbatim, so an edit there is
# what gets exercised here, not a transcription of it that can go stale.
_awk_local_port() {
	local src="$SCRIPT_DIR/bin/ports.sh" fn split
	fn=$(sed -n '/function local_port(/,/^	}/p' "$src")
	split=$(grep -E '^[[:space:]]+(arrow|address) = ' "$src")
	if [[ -z "$fn" || -z "$split" ]]; then
		echo "cannot lift the awk implementation out of $src — did it move or get renamed?" >&2
		return 1
	fi
	printf '%s\n' "$1" | awk "$fn"'
	{ name = $0
'"$split"'
	  print local_port(address) }'
}

# One input through both copies. Records a readable line per disagreement rather
# than failing on the first, so a run names every input that drifted.
_agree() {
	local input="$1" want="$2" label="$3" from_bash from_awk
	from_bash="$(rcc_local_port "$input")"
	if ! from_awk="$(_awk_local_port "$input")"; then
		FAILURES+=$'\n'"  $label: the awk copy could not be run at all"
		return
	fi
	if [[ "$from_bash" != "$from_awk" ]]; then
		FAILURES+=$'\n'"  $label: input '$input' -> bash gave '$from_bash', awk gave '$from_awk'"
	elif [[ "$from_bash" != "$want" ]]; then
		FAILURES+=$'\n'"  $label: input '$input' -> both gave '$from_bash', expected '$want'"
	fi
}

_report() {
	if [[ -n "$FAILURES" ]]; then
		echo "the two copies of the local-port rule disagree:$FAILURES" >&2
		return 1
	fi
}

# If the lift ever silently returns nothing, every comparison would be "" == ""
# and this whole file would pass while testing nothing. This is the canary.
@test "equivalence: the awk copy is actually reachable from its source" {
	run _awk_local_port '*:7000'
	[[ "$status" -eq 0 ]]
	[[ "$output" == "7000" ]]
}

@test "equivalence: bash and awk read the same port out of every shape" {
	_agree '*:7000' '7000' 'LISTEN IPv4, wildcard'
	_agree '127.0.0.1:8765' '8765' 'LISTEN IPv4, loopback'
	_agree '[fe80:e::479:7b38:ef37:a217]:56122' '56122' 'LISTEN IPv6, bracketed'
	_agree '[::1]:8080' '8080' 'LISTEN IPv6, loopback'
	_agree '172.20.10.3:51794->160.79.104.10:443' '51794' 'connected IPv4, arrow'
	_agree '[fe80::1]:56122->[fe80::2]:54343' '56122' 'connected IPv6, arrow'
	_agree '*:*' '*' 'unbound socket'
	_agree 'nocolonhere' '' 'no port at all'
	_agree '' '' 'empty field'
	_report
}

# Neither copy validates the port, and neither should: this rule reports what
# lsof said, and the range check belongs to _split_hostport in bin/fleet.sh,
# which reads a hand-written config instead. Pinned here because "fixing" it in
# one copy only is exactly how the two would come apart.
@test "equivalence: neither copy invents a validation the other lacks" {
	_agree 'mac.local:99999' '99999' 'port past 65535'
	_agree 'mac.local:0' '0' 'port zero'
	_agree 'mac.local:ssh' 'ssh' 'non-numeric port'
	_agree 'host:' '' 'colon with nothing after it'
	_report
}
