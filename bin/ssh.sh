#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

SSH_DIR="$HOME/.ssh"

show_ssh_help() {
	print_help_header "ssh" "Inspect and manage SSH keys (orphan, unprotected, permissions)" "[--export KEY] [--export-gpg [KEY]]"
	echo ""
	echo "  Inspection (default):"
	echo "    Scans ~/.ssh for unprotected keys (no passphrase), orphan keys (missing .pub),"
	echo "    and incorrect permissions — shows all findings in a table."
	echo ""
	echo "  Export:"
	echo "    --export KEY       Copy SSH public key to clipboard (default: id_ed25519)"
	echo "    --export-gpg [KEY] List GPG keys, or copy specific GPG/PGP public key to clipboard"
	echo ""
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
	print_section_header "Unprotected Keys"
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
					key_type=$(ssh-keygen -l -f "${key}.pub" 2>/dev/null | awk '{print $NF}' || echo "?")
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
	print_section_header "Orphan Keys"
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
	print_section_header "Key Permissions"
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
	print_success "Completed"
}

# ponytail: --export copies pubkey to clipboard, no need to handle every key type
if [[ "${1:-}" == "--export" ]]; then
	keyname="${2:-id_ed25519}"
	if [[ -f "$HOME/.ssh/${keyname}.pub" ]]; then
		pbcopy < "$HOME/.ssh/${keyname}.pub"
		echo "✓ Public key ${keyname}.pub copied to clipboard"
	else
		echo "✗ Key not found: ~/.ssh/${keyname}.pub" >&2
		exit 1
	fi
	exit 0
fi

# ponytail: --export-gpg lists or copies GPG public key; no key management, just clipboard
if [[ "${1:-}" == "--export-gpg" ]]; then
	gpg_key="${2:-}"
	if [[ -z "$gpg_key" ]]; then
		gpg --list-keys --keyid-format LONG 2>/dev/null || echo "No GPG keys found"
	else
		gpg_out=$(gpg --export --armor "$gpg_key" 2>/dev/null)
		if [[ -n "$gpg_out" ]]; then
			printf '%s' "$gpg_out" | pbcopy
			echo "✓ GPG public key $gpg_key copied to clipboard"
		else
			echo "✗ GPG key not found: $gpg_key" >&2
			exit 1
		fi
	fi
	exit 0
fi

main "$@"