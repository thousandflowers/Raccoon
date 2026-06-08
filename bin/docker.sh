#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_docker_help() {
	print_help_header "docker" "Show Docker images, containers, and space usage" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_docker_help
		exit 0
		;;
	--json)
		;;
	esac
done

main() {
	local use_global_progress=false
	if [[ -t 1 && "$JSON_OUTPUT" != "true" ]]; then
		use_global_progress=true
	fi

	if [[ "$use_global_progress" == "true" ]]; then
		init_global_progress 4
	fi

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		# JSON output: legacy behavior without progress bar
		echo '{"docker": "not implemented for JSON yet"}'
		return 0
	fi

	print_section_header "Docker Status"

	if ! command -v docker >/dev/null 2>&1; then
		if [[ "$use_global_progress" == "true" ]]; then
			finish_global_progress
		fi
		print_table_row "${RED}Docker is not installed or not running${NC}" 40
		print_table_row "${GRAY}Install Docker Desktop${NC}" 40
		print_success "Completed"
		return 0
	fi

	# Step 1: Images
	if [[ "$use_global_progress" == "true" ]]; then
		update_global_progress_info "docker: reading images..."
	fi
	local -a images_data=()
	local images
	images=$(docker images 2>/dev/null | tail -n +2 | head -10 || echo "")
	if [[ -n "$images" ]]; then
		local img_count
		img_count=$(echo "$images" | wc -l | xargs || echo "0")
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "docker: $img_count images found"
		fi
		while read -r line; do
			[[ -z "$line" ]] && continue
			local repo tag size
			repo=$(echo "$line" | awk '{print $1}')
			tag=$(echo "$line" | awk '{print $2}')
			size=$(echo "$line" | awk '{print $7, $8}')
			if [[ -n "$repo" ]]; then
				images_data+=("$repo|$tag|$size")
				if [[ "$use_global_progress" == "true" ]]; then
					append_progress_output "  $repo:$tag ($size)"
				fi
			fi
		done <<< "$images"
	else
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "docker: no images found"
		fi
	fi
	if [[ "$use_global_progress" == "true" ]]; then
		increment_global_progress
	fi

	# Step 2: Containers
	if [[ "$use_global_progress" == "true" ]]; then
		update_global_progress_info "docker: reading containers..."
	fi
	local -a containers_data=()
	local containers
	containers=$(docker ps -a 2>/dev/null | tail -n +2 | head -10 || echo "")
	if [[ -n "$containers" ]]; then
		local ctr_count
		ctr_count=$(echo "$containers" | wc -l | xargs || echo "0")
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "docker: $ctr_count containers found"
		fi
		while read -r line; do
			[[ -z "$line" ]] && continue
			local cid image status
			cid=$(echo "$line" | awk '{print $1}' | cut -c1-14)
			image=$(echo "$line" | awk '{print $2}')
			status=$(echo "$line" | awk '{print $NF}')
			if [[ -n "$cid" ]]; then
				containers_data+=("$cid|$image|$status")
				if [[ "$use_global_progress" == "true" ]]; then
					append_progress_output "  $cid ($status)"
				fi
			fi
		done <<< "$containers"
	else
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "docker: no containers found"
		fi
	fi
	if [[ "$use_global_progress" == "true" ]]; then
		increment_global_progress
	fi

	# Step 3: Volumes
	if [[ "$use_global_progress" == "true" ]]; then
		update_global_progress_info "docker: reading volumes..."
	fi
	local -a volumes_data=()
	local volumes
	volumes=$(docker volume ls 2>/dev/null | tail -n +2 || echo "")
	if [[ -n "$volumes" ]]; then
		local vol_count
		vol_count=$(echo "$volumes" | wc -l | xargs || echo "0")
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "docker: $vol_count volumes found"
		fi
		while read -r line; do
			[[ -z "$line" ]] && continue
			local vol_name driver
			vol_name=$(echo "$line" | awk '{print $2}')
			driver=$(echo "$line" | awk '{print $3}')
			if [[ -n "$vol_name" && "$vol_name" != "NAME" ]]; then
				volumes_data+=("$vol_name|$driver")
			fi
		done <<< "$volumes"
	else
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "docker: no volumes found"
		fi
	fi
	if [[ "$use_global_progress" == "true" ]]; then
		increment_global_progress
	fi

	# Step 4: Space Usage
	if [[ "$use_global_progress" == "true" ]]; then
		update_global_progress_info "docker: reading disk usage..."
	fi
	local -a space_data=()
	local sys_df
	sys_df=$(docker system df 2>/dev/null || echo "")
	if [[ -n "$sys_df" ]]; then
		while read -r line; do
			[[ -z "$line" ]] && continue
			local type size
			type=$(echo "$line" | awk '{print $1}')
			size=$(echo "$line" | awk '{print $2}')
			if [[ -n "$type" ]]; then
				space_data+=("$type|$size")
			fi
		done <<< "$(echo "$sys_df" | head -10)"
	else
		if [[ "$use_global_progress" == "true" ]]; then
			append_progress_output "docker: could not get disk usage"
		fi
	fi
	if [[ "$use_global_progress" == "true" ]]; then
		increment_global_progress
		finish_global_progress
	fi

	# Output: Images
	echo ""
	print_step 1 4 "Docker Images"
	print_table_header "Repository|Tag|Size" 25 15 10
	if [[ ${#images_data[@]} -eq 0 ]]; then
		print_table_row "${GRAY}No images found${NC}|-|" 25 15 10
	else
		for item in "${images_data[@]}"; do
			print_table_row "$item" 25 15 10
		done
	fi

	# Output: Containers
	echo ""
	print_step 2 4 "Docker Containers"
	print_table_header "Container ID|Image|Status" 14 20 15
	if [[ ${#containers_data[@]} -eq 0 ]]; then
		print_table_row "${GRAY}No containers found${NC}|-|" 14 20 15
	else
		for item in "${containers_data[@]}"; do
			print_table_row "$item" 14 20 15
		done
	fi

	# Output: Volumes
	echo ""
	print_step 3 4 "Docker Volumes"
	print_table_header "Volume Name|Driver" 30 15
	if [[ ${#volumes_data[@]} -eq 0 ]]; then
		print_table_row "${GRAY}No volumes found${NC}|" 30 15
	else
		for item in "${volumes_data[@]}"; do
			print_table_row "$item" 30 15
		done
	fi

	# Output: Space
	echo ""
	print_step 4 4 "Docker Space Usage"
	print_table_header "Type|Size" 25 20
	if [[ ${#space_data[@]} -eq 0 ]]; then
		print_table_row "${GRAY}Could not get info${NC}|" 25 20
	else
		for item in "${space_data[@]}"; do
			print_table_row "$item" 25 20
		done
	fi

	echo ""
	print_success "Completed"
}

main "$@"
