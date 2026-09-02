#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_docker_help() {
	echo "Usage: rcc docker [options]"
	echo ""
	echo "Show Docker images, containers, and space usage"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_docker_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		shift
		;;
	esac
done

# Docker's own --format strings, tab-separated, for both renderings. Parsing
# the human table by column was how the text report printed a CREATED
# fragment ("hours") as every container's status, put the item count in the
# Size column and read the header as a row, while --json put RECLAIMABLE in
# "size" and never emitted the size at all.
_docker_images() { docker images --format '{{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null || true; }
_docker_containers() { docker ps -a --format '{{.ID}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || true; }
_docker_volumes() { docker volume ls --format '{{.Name}}\t{{.Driver}}' 2>/dev/null || true; }
_docker_space() { docker system df --format '{{.Type}}\t{{.TotalCount}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null || true; }

_docker_installed() { command -v docker >/dev/null 2>&1; }
# The CLI can be there with the daemon down. Every list is empty then, and
# "No images found" under a green tick is the wrong thing to say about it.
_docker_running() { docker info >/dev/null 2>&1; }

# Everything the report shows, as one document. The question this command
# answers is "is Docker there, and what is it holding", so absence is a value
# and not an error: a Mac without Docker gets installed:false, not a failure.
_json_report() {
	local first a b c d e
	printf '{\n'
	printf '  "installed": %s,\n' "$(_docker_installed && echo true || echo false)"

	if ! _docker_installed || ! _docker_running; then
		printf '  "running": false,\n  "images": [],\n  "containers": [],\n  "volumes": [],\n  "space": []\n}\n'
		return 0
	fi
	printf '  "running": true,\n'

	printf '  "images": ['
	first=1
	while IFS=$'\t' read -r a b c; do
		[[ -n "$a" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"repository": %s, "tag": %s, "size": %s}' \
			"$(rcc_json_string "$a")" "$(rcc_json_string "$b")" "$(rcc_json_string "$c")"
	done < <(_docker_images)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "containers": ['
	first=1
	while IFS=$'\t' read -r a b c; do
		[[ -n "$a" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"id": %s, "image": %s, "status": %s}' \
			"$(rcc_json_string "$a")" "$(rcc_json_string "$b")" "$(rcc_json_string "$c")"
	done < <(_docker_containers)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "volumes": ['
	first=1
	while IFS=$'\t' read -r a b; do
		[[ -n "$a" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "driver": %s}' "$(rcc_json_string "$a")" "$(rcc_json_string "$b")"
	done < <(_docker_volumes)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "space": ['
	first=1
	while IFS=$'\t' read -r a b c d e; do
		[[ -n "$a" ]] || continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"type": %s, "total": %s, "active": %s, "size": %s, "reclaimable": %s}' \
			"$(rcc_json_string "$a")" "$(rcc_json_number "$b")" "$(rcc_json_number "$c")" \
			"$(rcc_json_string "$d")" "$(rcc_json_string "$e")"
	done < <(_docker_space)
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

# A table of up to ten rows, then "and N more": a list cut short says so.
_docker_table() {
	local rows="$1" widths="$2" shown=0 total line
	total=$(printf '%s\n' "$rows" | grep -c . || true)
	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		if [[ $shown -lt 10 ]]; then
			# shellcheck disable=SC2086
			print_table_row "${line//$'\t'/|}" $widths
		fi
		((shown++)) || true
	done <<< "$rows"
	if [[ $total -gt 10 ]]; then
		# shellcheck disable=SC2086
		print_table_row "${GRAY}and $((total - 10)) more (rcc docker --json lists them all)${NC}" $widths
	fi
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi

	print_section_header "Docker Status"

	if ! _docker_installed; then
		print_table_row "${YELLOW}Docker is not installed${NC}" 40
		print_table_row "${GRAY}Install Docker Desktop, or OrbStack, or Colima${NC}" 40
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi
	if ! _docker_running; then
		print_table_row "${YELLOW}Docker is installed, but the daemon is not running${NC}" 60
		print_table_row "${GRAY}Start Docker Desktop (or the engine you use) and run again${NC}" 60
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	local rows
	echo "${GRAY}[1/4] Docker Images...${NC}"
	print_table_header "Repository|Tag|Size" 30 15 10
	rows=$(_docker_images)
	if [[ -n "$rows" ]]; then
		_docker_table "$rows" "30 15 10"
	else
		print_table_row "${GRAY}No images${NC}|-|-" 30 15 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] Docker Containers...${NC}"
	print_table_header "Container ID|Image|Status" 14 24 24
	rows=$(_docker_containers)
	if [[ -n "$rows" ]]; then
		_docker_table "$rows" "14 24 24"
	else
		print_table_row "${GRAY}No containers${NC}|-|-" 14 24 24
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] Docker Volumes...${NC}"
	print_table_header "Volume Name|Driver" 40 10
	rows=$(_docker_volumes)
	if [[ -n "$rows" ]]; then
		print_table_row "${GRAY}Total: $(printf '%s\n' "$rows" | grep -c .) volumes${NC}|" 40 10
		_docker_table "$rows" "40 10"
	else
		print_table_row "${GRAY}No volumes${NC}|-" 40 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Space Usage...${NC}"
	print_table_header "Type|Items|Active|Size|Reclaimable" 16 6 6 10 14
	rows=$(_docker_space)
	if [[ -n "$rows" ]]; then
		_docker_table "$rows" "16 6 6 10 14"
	else
		print_table_row "${GRAY}Could not get info${NC}|-|-|-|-" 16 6 6 10 14
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
