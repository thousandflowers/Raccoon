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

# Everything the report shows, as one document. The question this command
# answers is "is Docker there, and what is it holding", so absence is a value
# and not an error: a Mac without Docker gets installed:false, not a failure.
_json_report() {
	local images containers volumes sys_df first
	printf '{\n'
	printf '  "installed": %s,\n' "$(command -v docker >/dev/null 2>&1 && echo true || echo false)"

	if ! command -v docker >/dev/null 2>&1; then
		printf '  "running": false,\n  "images": [],\n  "containers": [],\n  "volumes": [],\n  "space": []\n}\n'
		return 0
	fi

	# `docker info` fails when the daemon is down but the CLI is installed:
	# two different states the text report collapsed into one line.
	printf '  "running": %s,\n' "$(docker info >/dev/null 2>&1 && echo true || echo false)"

	printf '  "images": ['
	first=1
	while read -r line; do
		[[ -z "$line" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"repository": %s, "tag": %s, "size": %s}' \
			"$(rcc_json_string "$(echo "$line" | awk '{print $1}')")" \
			"$(rcc_json_string "$(echo "$line" | awk '{print $2}')")" \
			"$(rcc_json_string "$(echo "$line" | awk '{print $NF}')")"
	done < <(docker images 2>/dev/null | tail -n +2)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "containers": ['
	first=1
	while read -r line; do
		[[ -z "$line" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"id": %s, "image": %s, "status": %s}' \
			"$(rcc_json_string "$(echo "$line" | awk '{print $1}')")" \
			"$(rcc_json_string "$(echo "$line" | awk '{print $2}')")" \
			"$(rcc_json_string "$(echo "$line" | sed -E 's/.*[[:space:]]{2,}(Up|Exited|Created|Restarting|Paused|Dead)/\1/;s/[[:space:]]{2,}.*$//')")"
	done < <(docker ps -a 2>/dev/null | tail -n +2)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "volumes": ['
	first=1
	while read -r line; do
		[[ -z "$line" ]] && continue
		local name driver
		driver=$(echo "$line" | awk '{print $1}')
		name=$(echo "$line" | awk '{print $2}')
		[[ -z "$name" || "$name" == "NAME" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "driver": %s}' \
			"$(rcc_json_string "$name")" "$(rcc_json_string "$driver")"
	done < <(docker volume ls 2>/dev/null | tail -n +2)
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "space": ['
	first=1
	while read -r line; do
		[[ -z "$line" ]] && continue
		local type_ size reclaim
		type_=$(echo "$line" | sed -E 's/[[:space:]]{2,}.*$//')
		[[ -z "$type_" || "$type_" == "TYPE" ]] && continue
		size=$(echo "$line" | awk '{print $(NF-1)}')
		reclaim=$(echo "$line" | awk '{print $NF}')
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"type": %s, "size": %s, "reclaimable": %s}' \
			"$(rcc_json_string "$type_")" "$(rcc_json_string "$size")" \
			"$(rcc_json_string "$reclaim")"
	done < <(docker system df 2>/dev/null)
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi

	print_section_header "Docker Status"

	if ! command -v docker >/dev/null 2>&1; then
		print_table_row "${RED}Docker is not installed or not running${NC}" 40
		print_table_row "${GRAY}Install Docker Desktop${NC}" 40
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	echo "${GRAY}[1/4] Docker Images...${NC}"
	print_table_header "Repository|Tag|Size" 25 15 10

	local images
	images=$(docker images 2>/dev/null | tail -n +2 | head -10 || echo "")
	if [[ -n "$images" ]]; then
		echo "$images" | while read -r line; do
			[[ -z "$line" ]] && continue
			local repo tag size
			repo=$(echo "$line" | awk '{print $1}')
			tag=$(echo "$line" | awk '{print $2}')
			size=$(echo "$line" | awk '{print $NF}')
			[[ -n "$repo" ]] && print_table_row "$repo|$tag|$size" 25 15 10
		done
	else
		print_table_row "${GRAY}No images found${NC}|-|-" 25 15 10
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] Docker Containers...${NC}"
	print_table_header "Container ID|Image|Status" 14 20 15

	local containers
	containers=$(docker ps -a 2>/dev/null | tail -n +2 | head -10 || echo "")
	if [[ -n "$containers" ]]; then
		echo "$containers" | while read -r line; do
			[[ -z "$line" ]] && continue
			local cid image status
			cid=$(echo "$line" | awk '{print $1}' | cut -c1-14)
			image=$(echo "$line" | awk '{print $2}')
			status=$(echo "$line" | awk '{print $5}')
			[[ -n "$cid" ]] && print_table_row "$cid|$image|$status" 14 20 15
		done
	else
		print_table_row "${GRAY}No containers found${NC}|-|-" 14 20 15
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] Docker Volumes...${NC}"
	print_table_header "Volume Name|Driver" 30 15

	local volumes
	volumes=$(docker volume ls 2>/dev/null | tail -n +2 || echo "")
	if [[ -n "$volumes" ]]; then
		local vol_count
		vol_count=$(echo "$volumes" | wc -l | xargs || echo "0")
		print_table_row "Total volumes|$vol_count" 30 15
		echo "$volumes" | while read -r line; do
			[[ -z "$line" ]] && continue
			local vol_name driver
			vol_name=$(echo "$line" | awk '{print $2}')
			driver=$(echo "$line" | awk '{print $1}')
			[[ -n "$vol_name" && "$vol_name" != "NAME" ]] && print_table_row "$vol_name|$driver" 30 15
		done
	else
		print_table_row "${GRAY}No volumes found${NC}|-" 30 15
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Space Usage...${NC}"
	print_table_header "Type|Size" 25 20

	local sys_df
	sys_df=$(docker system df 2>/dev/null || echo "")
	if [[ -n "$sys_df" ]]; then
		echo "$sys_df" | head -10 | while read -r line; do
			[[ -z "$line" ]] && continue
			local type size
			type=$(echo "$line" | awk '{print $1}')
			size=$(echo "$line" | awk '{print $2}')
			[[ -n "$type" ]] && print_table_row "$type|$size" 25 20
		done
	else
		print_table_row "${GRAY}Could not get info${NC}|-" 25 20
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"
