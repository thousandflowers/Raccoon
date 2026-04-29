#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

SSH_DIR="$HOME/.ssh"

show_ssh_help() {
	echo "Usage: rcc ssh [options]"
	echo ""
	echo "Check SSH keys and configuration"
	echo ""
	echo "Options:"
	echo "  --help, -h      Show this help"
}

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_ssh_help
		exit 0
		;;
	*)
		;;
	esac
done

check_unprotected_keys() {
	echo ""
	echo "Unprotected Keys"
	print_table_header "Key|Type|Status" 30 15 15

	local found=0
	if [[ -d "$SSH_DIR" ]]; then
		for key in "$SSH_DIR"/id_*; do
			[[ -f "$key" ]] || continue
			[[ "$key" == *.pub ]] && continue

			local key_name
			key_name=$(basename "$key")

			if ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1; then
				local key_type=""
				if [[ -f "${key}.pub" ]]; then
					key_type=$(ssh-keygen -l -f "${key}.pub" 2>/dev/null | awk '{print $4}' || echo "?")
				else
					key_type="?"
				fi
				print_table_row "$key_name|$key_type|${YELLOW}NO PASSPHRASE${NC}" 30 15 15
				((found++)) || true
			fi
		done
	fi

	if [[ $found -eq 0 ]]; then
		print_table_row "None|All protected|${GRAY}OK${NC}" 30 15 15
	fi
}

check_orphan_keys() {
	echo ""
	echo "Orphan Keys"
	print_table_header "Key|Status" 30 15

	local found=0
	if [[ -d "$SSH_DIR" ]]; then
		for key in "$SSH_DIR"/id_*; do
			[[ -f "$key" ]] || continue
			[[ "$key" == *.pub ]] && continue

			local key_name
			key_name=$(basename "$key")

			if [[ ! -f "${key}.pub" ]]; then
				print_table_row "$key_name|${YELLOW}No .pub file${NC}" 30 15
				((found++)) || true
			fi
		done
	fi

	if [[ $found -eq 0 ]]; then
		print_table_row "None|${GRAY}OK${NC}" 30 15
	fi
}

check_key_permissions() {
	echo ""
	echo "Key Permissions"
	print_table_header "Key|Perms|Status" 30 10 15

	local found=0
	if [[ -d "$SSH_DIR" ]]; then
		for key in "$SSH_DIR"/id_*; do
			[[ -f "$key" ]] || continue
			[[ "$key" == *.pub ]] && continue

			local key_name
			key_name=$(basename "$key")

			local perms
			perms=$(stat -f %A "$key" 2>/dev/null || echo "000")

			if [[ "$perms" != "600" ]]; then
				print_table_row "$key_name|$perms|${RED}Should be 600${NC}" 30 10 15
			else
				print_table_row "$key_name|$perms|${GRAY}OK${NC}" 30 10 15
			fi
			((found++)) || true
		done
	fi
}

main() {
	check_unprotected_keys
	check_orphan_keys
	check_key_permissions

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"