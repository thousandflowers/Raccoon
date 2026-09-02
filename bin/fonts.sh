#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_fonts_help() {
	echo "Usage: rcc fonts [options]"
	echo ""
	echo "Show installed fonts and check for duplicates"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

# shellcheck disable=SC2034
	JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_fonts_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

# A directory that does not exist is zero fonts, not a failure. find exits
# non-zero on a missing path, pipefail propagates it and set -e kills the
# script: a Mac with no ~/Library/Fonts printed nothing at all. Same trap as
# bin/battery.sh.
_fonts_count_in() {
	[[ -d "$1" ]] || { printf '0'; return 0; }
	find "$1" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ' || printf '0'
}

# Every place macOS keeps fonts, not the two a person can write to.
#
# The report used to count /Library/Fonts and ~/Library/Fonts alone, then print
# fontconfig's number beside it: `installed: 812` above `fonts: 940`, two
# figures for one question and no word about the gap. The gap was
# /System/Library/Fonts and its Supplemental folder — 373 faces on a stock Mac,
# a third of everything installed, invisible to the report that claimed to
# count what was installed.
#
# They are read-only and nobody removes them, which is a reason to label them,
# not a reason to pretend they are not there.
_FONT_DIRS=(
	/System/Library/Fonts
	/System/Library/Fonts/Supplemental
	/Library/Fonts
	"$HOME/Library/Fonts"
)

# How many installed font files fontconfig cannot read — the one thing in this
# report anyone has to act on.
#
# One fc-scan for every font, not one per font. Scanning ~800 files individually
# took fifteen seconds, past the ten Raycast gives a command: the process was
# killed mid-document and the reader was told rcc emits broken JSON, when the
# only thing wrong was that it was slow. The same list now costs half a second.
#
# fc-scan prints a line for each file it could read, so a candidate that never
# comes back is one it could not. Counting the difference rather than the
# failures keeps the answer identical to the per-file version — checked against
# planted unreadable files — without a process per font.
_fonts_corrupted() {
	command -v fc-scan >/dev/null 2>&1 || { printf '0'; return 0; }
	local dirs=("${_FONT_DIRS[@]}")
	# `wc -l`, not `grep -c`: grep exits 1 when it counts nothing, and this
	# repository has shipped that bug twice (see lib/audit/checks.sh:344).
	local n
	n=$(comm -23 \
		<(find "${dirs[@]}" -maxdepth 1 -type f \
			\( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) 2>/dev/null \
			| sort -u) \
		<(fc-scan --format '%{file}\n' "${dirs[@]}" 2>/dev/null | sort -u) \
		| wc -l)
	printf '%s' "$((n))"
}

_json_report() {
	local fc_available=false fonts=0 families=0 dupes=0 installed=0 dir count
	installed=0
	if command -v fc-list >/dev/null 2>&1; then
		fc_available=true
		fonts=$(fc-list : family 2>/dev/null | wc -l | tr -d ' ')
		families=$(fc-list : family 2>/dev/null | sort -u | wc -l | tr -d ' ')
		dupes=$(fc-list : family 2>/dev/null | sort | uniq -d | wc -l | tr -d ' ')
	fi
	printf '{\n'
	printf '  "sources": [\n'
	local first=1
	for dir in "${_FONT_DIRS[@]}"; do
		count=$(_fonts_count_in "$dir")
		installed=$((installed + count))
		[[ $first -eq 1 ]] || printf ',\n'
		first=0
		printf '    {"path": %s, "count": %s}' \
			"$(rcc_json_string "$dir")" "$(rcc_json_number "$count")"
	done
	printf '\n  ],\n'
	printf '  "installed": %s,\n' "$(rcc_json_number "$installed")"
	# Every count here comes out of a pipeline that can produce nothing at all -
	# fc-list missing, a cache it cannot read, a run that was cut short - and an
	# empty string interpolated with %s writes `"families": ,` into the document.
	# The reader is then told the CLI is too old, which is the wrong thing to be
	# told and the reason this reached a user.
	printf '  "fontconfig": {"available": %s, "fonts": %s, "families": %s, "duplicate_families": %s},\n' \
		"$fc_available" \
		"$(rcc_json_number "$fonts")" \
		"$(rcc_json_number "$families")" \
		"$(rcc_json_number "$dupes")"
	printf '  "corrupted": %s\n}\n' "$(rcc_json_number "$(_fonts_corrupted)")"
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	print_section_header "Fonts Status"

	# Same list the JSON walks. It used to be two directories here and two
	# again below, written out twice, and both stopped short of the system
	# folders that hold a third of the fonts on the machine.
	local total=0 dir count user_fonts=0
	print_table_header "Source|Count" 34 20
	for dir in "${_FONT_DIRS[@]}"; do
		count=$(_fonts_count_in "$dir")
		total=$((total + count))
		[[ "$dir" == "$HOME/Library/Fonts" ]] && user_fonts=$count
		# `~`, not the full home path: it is what a person reads, and the real
		# one overflows the column on any account with a long username.
		print_table_row "${dir/#$HOME/~}|$count" 34 20
	done

	print_success "Font sources scanned"

	echo ""
	echo "${GRAY}[2/4] User Fonts...${NC}"
	print_table_header "Source|Count" 34 20
	# shellcheck disable=SC2088  # the tilde is label text, not a path to open
	print_table_row "~/Library/Fonts|$user_fonts" 34 20

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] FontConfig Catalog...${NC}"

	print_table_header "Metric|Count" 25 20

	if command -v fc-list >/dev/null 2>&1; then
		local fc_count fc_families
		fc_count=$(fc-list : family 2>/dev/null | wc -l | xargs || echo "0")
		fc_families=$(fc-list : family 2>/dev/null | sort -u | wc -l | xargs || echo "0")
		print_table_row "Total fonts|$fc_count" 25 20
		print_table_row "Unique families|$fc_families" 25 20
	else
		print_table_row "fontconfig|${YELLOW}not installed${NC}" 25 20
	fi

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Duplicate & Corrupt Check...${NC}"

	print_table_header "Check|Result" 25 20

	if command -v fc-list >/dev/null 2>&1; then
		local duplicates
		duplicates=$(fc-list : family 2>/dev/null | sort | uniq -d | wc -l | xargs || echo "0")
		if [[ "$duplicates" -gt 0 ]]; then
			print_table_row "Duplicates|${YELLOW}${duplicates} families${NC}" 25 20
		else
			print_table_row "Duplicates|${GREEN}none found${NC}" 25 20
		fi

		# One call, and the same one the JSON uses. This branch kept its own
		# copy — an `ls` glob and an fc-scan per file — so the report the TUI
		# reads stayed fifteen seconds long after the JSON was made fast, and
		# the two could have disagreed about the same machine.
		print_table_row "Corrupted fonts|$(_fonts_corrupted)" 25 20
	else
		print_table_row "Checks|${GRAY}skipped${NC}" 25 20
	fi

	print_table_row "${GRAY}Total installed${NC}|$total fonts" 25 20

	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"