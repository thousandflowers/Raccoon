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
		echo "Unknown option: $arg"
		echo "Usage: rcc ssh"
		exit 1
		;;
	esac
done

check_unprotected_keys() {
	echo ""
	echo "Unprotected Keys (no passphrase)"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
					key_type=$(ssh-keygen -l -f "${key}.pub" 2>/dev/null | awk '{print $4}' || echo "unknown")
				else
					key_type="?"
				fi
				echo -e "  ${YELLOW}${ICON_ERROR} $key_name ($key_type) has NO passphrase${NC}"
				((found++))
			fi
		done
	fi

	if [[ $found -eq 0 ]]; then
		echo -e "  ${GRAY}All keys are protected${NC}"
	fi
}

check_orphan_keys() {
	echo ""
	echo "Orphan Keys (private key without .pub)"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	local found=0
	if [[ -d "$SSH_DIR" ]]; then
		for key in "$SSH_DIR"/id_*; do
			[[ -f "$key" ]] || continue
			[[ "$key" == *.pub ]] && continue

			local key_name
			key_name=$(basename "$key")

			if [[ ! -f "${key}.pub" ]]; then
				echo -e "  ${YELLOW}${ICON_ERROR} $key_name (no .pub file)${NC}"
				((found++))
			fi
		done
	fi

	if [[ $found -eq 0 ]]; then
		echo -e "  ${GRAY}All private keys have matching .pub files${NC}"
	fi
}

check_key_permissions() {
	echo ""
	echo "Key Permissions"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
				echo -e "  ${RED}${ICON_ERROR} $key_name ($perms) - should be 600${NC}"
			else
				echo -e "  ${GRAY}$key_name (600 ✓)${NC}"
			fi
			((found++))
		done
	fi

	if [[ $found -eq 0 ]]; then
		echo -e "  ${GRAY}No private keys found${NC}"
	fi
}

check_ssh_dir_permissions() {
	echo ""
	echo "Directory Permissions"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	if [[ -d "$SSH_DIR" ]]; then
		local dir_perms
		dir_perms=$(stat -f %A "$SSH_DIR" 2>/dev/null || echo "000")

		if [[ "$dir_perms" != "700" ]]; then
			echo -e "  ${RED}${ICON_ERROR} ~/.ssh ($dir_perms) - should be 700${NC}"
		else
			echo -e "  ${GRAY}~/.ssh (700 ✓)${NC}"
		fi
	else
		echo -e "  ${GRAY}~/.ssh does not exist${NC}"
	fi
}

check_ssh_config() {
	echo ""
	echo "SSH Config"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	if [[ -f "$SSH_DIR/config" ]]; then
		local host_count
		host_count=$(grep -c "^Host " "$SSH_DIR/config" 2>/dev/null || echo "0")
		echo -e "  ${GREEN}Config file exists${NC} (${host_count} host entries)"

		local weak_configs=0
		if grep -qi "PasswordAuthentication yes" "$SSH_DIR/config" 2>/dev/null; then
			echo -e "  ${YELLOW}${ICON_ERROR} PasswordAuthentication yes found (insecure)${NC}"
			((weak_configs++))
		fi
		if [[ $weak_configs -eq 0 ]]; then
			echo -e "  ${GRAY}No weak configurations found${NC}"
		fi
	else
		echo -e "  ${GRAY}No config file${NC}"
	fi
}

main() {
	print_section_header "SSH Keys & Config"

	show_progress_bar \
		"Unprotected keys:check_unprotected_keys" \
		"Orphan keys:check_orphan_keys" \
		"Directory permissions:check_ssh_dir_permissions" \
		"Key permissions:check_key_permissions" \
		"SSH config:check_ssh_config"
}

main "$@"