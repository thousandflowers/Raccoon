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

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_docker_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Docker Status"

	if ! command -v docker >/dev/null 2>&1; then
		echo "${RED}Docker is not installed or not running${NC}"
		echo "${GRAY}Install Docker Desktop: https://www.docker.com/products/docker-desktop${NC}"
		echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
		return 0
	fi

	echo "${GRAY}[1/4] Docker Images...${NC}"
	local images
	images=$(docker images 2>/dev/null | tail -n +2 | head -10 || echo "")
	if [[ -n "$images" ]]; then
		printf "  %-20s %10s %12s\n" "REPOSITORY" "TAG" "SIZE"
		echo "${GRAY}─────────────────────────────────────────${NC}"
		echo "$images" | while read -r line; do
			[[ -z "$line" ]] && continue
			local repo tag size
			repo=$(echo "$line" | awk '{print $1}')
			tag=$(echo "$line" | awk '{print $2}')
			size=$(echo "$line" | awk '{print $7, $8}')
			[[ -n "$repo" ]] && printf "  %-20s %10s %12s\n" "$repo" "$tag" "$size"
		done
	else
		echo "  ${GRAY}No Docker images found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] Docker Containers...${NC}"
	local containers
	containers=$(docker ps -a 2>/dev/null | tail -n +2 | head -10 || echo "")
	if [[ -n "$containers" ]]; then
		printf "  %-14s %-18s %-12s\n" "CONTAINER ID" "IMAGE" "STATUS"
		echo "${GRAY}─────────────────────────────────────────────────────${NC}"
		echo "$containers" | while read -r line; do
			[[ -z "$line" ]] && continue
			local cid image status
			cid=$(echo "$line" | awk '{print $1}' | cut -c1-14)
			image=$(echo "$line" | awk '{print $2}')
			status=$(echo "$line" | awk '{print $NF}')
			[[ -n "$cid" ]] && printf "  %-14s %-18s %-12s\n" "$cid" "$image" "$status"
		done
	else
		echo "  ${GRAY}No Docker containers found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] Docker Volumes...${NC}"
	local volumes
	volumes=$(docker volume ls 2>/dev/null | tail -n +2 | head -5 || echo "")
	if [[ -n "$volumes" ]]; then
		local vol_count
		vol_count=$(docker volume ls 2>/dev/null | tail -n +2 | wc -l | xargs || echo "0")
		printf "  Total volumes: %s\n" "$vol_count"
		echo "$volumes" | while read -r line; do
			[[ -z "$line" ]] && continue
			local vol_name driver
			vol_name=$(echo "$line" | awk '{print $2}')
			driver=$(echo "$line" | awk '{print $3}')
			[[ -n "$vol_name" && "$vol_name" != "NAME" ]] && echo "  $vol_name ($driver)"
		done
	else
		echo "  ${GRAY}No Docker volumes found${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Space Usage (docker system df)...${NC}"
	local sys_df
	sys_df=$(docker system df 2>/dev/null || echo "")
	if [[ -n "$sys_df" ]]; then
		echo "$sys_df" | head -10 | while read -r line; do
			[[ -z "$line" ]] && continue
			echo "  $line"
		done
	else
		echo "  ${GRAY}Could not get Docker space info${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"