#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_backup_help() {
	print_help_header "backup" "Check Time Machine backup status" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_backup_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

# One field out of `tmutil destinationinfo`, by name.
#
# Both readers of this were broken, and between them they made every Mac with
# a destination report "Not configured":
#
#   - tmutil pads its field names ("Name          : Backup di x"), so the
#     grep for "Name:" matched nothing at all - not one line, on any machine.
#   - the XML fallback could not save it: `perl -wne` reads one line at a
#     time, and <key>Name</key> and its <string> are on separate lines, so a
#     pattern spanning both could never match however many /s it carried.
#
# The padded form answers first because it needs no second call; the XML is
# kept because tmutil drops fields from the plain output during a backup, and
# it is slurped now so the pattern can span lines.
_tm_field() {
	local key="$1" value
	value=$(tmutil destinationinfo 2>/dev/null |
		awk -F' *: *' -v k="$key" '$1 == k { print $2; exit }' || printf '')
	if [[ -z "$value" ]]; then
		value=$(tmutil destinationinfo -X 2>/dev/null |
			perl -0777 -wne 'print $1 if /<key>'"$key"'<\/key>\s*<string>(.*?)<\/string>/s' \
			2>/dev/null || printf '')
	fi
	printf '%s' "$value"
}

check_tm_destination() {
	local dest kind
	dest=$(_tm_field Name)
	kind=$(_tm_field Kind)

	print_table_header "Setting|Value" 20 30

	if [[ -z "$dest" ]]; then
		print_table_row "Destination|${RED}Not configured${NC}" 20 30
		return 0
	fi

	print_table_row "Destination|${GREEN}${dest}${NC}" 20 30
	[[ -n "$kind" ]] && print_table_row "Kind|$kind" 20 30
}

check_tm_phase() {
	local phase
	phase=$(tmutil currentphase 2>/dev/null || echo "unknown")
	case "$phase" in
		BackupNotRunning) phase="${GREEN}Idle${NC}" ;;
		BackupRunning) phase="${YELLOW}Backing up...${NC}" ;;
		*) phase="${GRAY}$phase${NC}" ;;
	esac
	print_table_row "Status|$phase" 20 30
}

check_last_backup() {
	local last_backup
	last_backup=$(tmutil latestbackup 2>/dev/null || echo "")

	print_table_header "Last Backup|When" 20 30

	if [[ -z "$last_backup" ]]; then
		# "No backup found" was said to a Mac holding a dozen of them. tmutil
		# latestbackup answers for the destination, and it fails whenever the
		# destination is not mounted - which is the normal state of a laptop.
		# The snapshots on the internal disk are backups too, and they are
		# listed by check_local_snapshots below, so this row says only what it
		# actually knows: the destination has nothing to show right now.
		local snaps
		snaps=$(_backup_snapshot_count)
		if [[ "${snaps:-0}" -gt 0 ]]; then
			print_table_row "Backup|${GRAY}destination not mounted${NC}" 20 30
		else
			print_table_row "Backup|${YELLOW}No backup found${NC}" 20 30
		fi
		return 0
	fi

	local backup_date
	backup_date=$(basename "$last_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")

	local now
	now=$(date +%s)
	local backup_ts
	backup_ts=$(date -j -f "%Y-%m-%d" "$backup_date" +%s 2>/dev/null || echo "0")
	local diff=$(((now - backup_ts) / 3600))

	if [[ $diff -lt 24 ]]; then
		print_table_row "Backup|${GREEN}${backup_date} (${diff}h ago)${NC}" 20 30
	elif [[ $diff -lt 168 ]]; then
		print_table_row "Backup|${YELLOW}${backup_date} (${diff}h ago)${NC}" 20 30
	else
		print_table_row "Backup|${RED}${backup_date} (${diff}h overdue!)${NC}" 20 30
	fi
}

check_tm_exclusions() {
	local excl_count=0
	if mdfind "kMDItemFSLabel = 6" 2>/dev/null | head -1 | grep -q .; then
		echo ""
		echo "${GRAY}Exclusions (Spotlight-tagged)...${NC}"
		while IFS= read -r excl_path; do
			[[ -z "$excl_path" ]] && continue
			echo "  ${GRAY}$excl_path${NC}"
			((excl_count++)) || true
		done < <(mdfind "kMDItemFSLabel = 6" 2>/dev/null | head -10)
	else
		# ponytail: mdfind returns nothing when no exclusions; no news is good news
		:
	fi
}

# Hours since the last backup, or -1 when there has never been one. The number
# is what decides whether this is fine, late, or a problem: a date on its own
# needs the reader to do the arithmetic.
_backup_age_hours() {
	local latest date_ ts now
	latest=$(tmutil latestbackup 2>/dev/null || printf '')
	[[ -n "$latest" ]] || { printf -- '-1'; return 0; }
	date_=$(basename "$latest" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || printf '')
	[[ -n "$date_" ]] || { printf -- '-1'; return 0; }
	ts=$(date -j -f "%Y-%m-%d" "$date_" +%s 2>/dev/null || printf '0')
	[[ "$ts" != "0" ]] || { printf -- '-1'; return 0; }
	now=$(date +%s)
	printf '%s' "$(((now - ts) / 3600))"
}

# Local snapshots: Time Machine's other half.
#
# When the backup disk is not attached, Time Machine keeps hourly snapshots on
# the internal disk instead, and they hold blocks belonging to files already
# deleted. A backup report that speaks only of the external destination misses
# the copies that are actually on this machine, and misses the reason its disk
# never empties.
#
# Asked of the Data volume by name: `diskutil apfs listSnapshots /` answers for
# the sealed System volume and finds one OS-update snapshot, so a report built
# on that says 1 where the truth is two dozen. Neither call needs sudo.
_backup_can_read_snapshots() {
	command -v diskutil >/dev/null 2>&1
}

_backup_snapshot_count() {
	_backup_can_read_snapshots || { printf '0'; return 0; }
	diskutil apfs listSnapshots /System/Volumes/Data 2>/dev/null \
		| grep -c 'com.apple.TimeMachine' || true
}

# The snapshot names, newest last. diskutil prints "|   Name:  com.apple..."
# so the name is the last field of the lines that carry one.
_backup_snapshot_names() {
	_backup_can_read_snapshots || return 0
	diskutil apfs listSnapshots /System/Volumes/Data 2>/dev/null |
		awk '/com\.apple\.TimeMachine/ { print $NF }' || true
}

# The count alone does not say how far back the copies go, which is the whole
# question a backup report is asked. Newest and oldest bound it in two rows.
check_local_snapshots() {
	local count
	count=$(_backup_snapshot_count)

	print_table_header "Local snapshots|When" 20 30

	if [[ "${count:-0}" -eq 0 ]]; then
		print_table_row "Snapshots|${GRAY}none${NC}" 20 30
		return 0
	fi

	print_table_row "Snapshots|${GREEN}${count} on this disk${NC}" 20 30

	local names newest oldest
	names=$(_backup_snapshot_names)
	[[ -n "$names" ]] || return 0
	newest=$(printf '%s\n' "$names" | tail -1)
	oldest=$(printf '%s\n' "$names" | head -1)
	print_table_row "Newest|$(_snapshot_when "$newest")" 20 30
	[[ "$newest" == "$oldest" ]] || print_table_row "Oldest|$(_snapshot_when "$oldest")" 20 30
}

# com.apple.TimeMachine.2026-09-07-180811.local -> 2026-09-07 18:08
_snapshot_when() {
	printf '%s' "$1" | sed -E 's/.*\.([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})([0-9]{2})[0-9]{2}.*/\1 \2:\3/'
}

_json_report() {
	local dest kind phase latest date_ hours first path
	dest=$(_tm_field Name)
	kind=$(_tm_field Kind)
	phase=$(tmutil currentphase 2>/dev/null || printf 'unknown')
	latest=$(tmutil latestbackup 2>/dev/null || printf '')
	date_=$(basename "${latest:-}" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || printf '')
	hours=$(_backup_age_hours)

	printf '{\n'
	printf '  "destination": {"configured": %s, "name": %s, "kind": %s},\n' \
		"$([[ -n "$dest" ]] && echo true || echo false)" \
		"$(rcc_json_string "$dest")" "$(rcc_json_string "$kind")"
	printf '  "phase": %s,\n' "$(rcc_json_string "$phase")"
	printf '  "running": %s,\n' "$([[ "$phase" != "BackupNotRunning" && "$phase" != "unknown" ]] && echo true || echo false)"
	printf '  "last_backup": {"date": %s, "hours_ago": %s},\n' \
		"$(rcc_json_string "$date_")" "$hours"

	local snap_ok="false"
	_backup_can_read_snapshots && snap_ok="true"
	printf '  "local_snapshots": {"available": %s, "count": %s},\n' \
		"$snap_ok" "$(rcc_json_number "$(_backup_snapshot_count)")"

	printf '  "exclusions": ['
	first=1
	while IFS= read -r path; do
		[[ -z "$path" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$path")"
	done < <(mdfind "kMDItemFSLabel = 6" 2>/dev/null | head -10 || true)
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	print_section_header "Time Machine"
	check_tm_destination
	check_tm_phase
	check_last_backup
	check_local_snapshots
	check_tm_exclusions

	echo ""
	print_success "Completed"
}

main "$@"