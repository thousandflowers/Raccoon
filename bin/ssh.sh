#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

SSH_DIR="$HOME/.ssh"

show_ssh_help() {
	print_help_header "ssh" "Inspect and manage SSH keys (orphan, unprotected, permissions)" "[--json] [--export KEY] [--export-gpg [KEY]]"
	echo "  --json          Output in JSON format"
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

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_ssh_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		;;
	esac
done

# One record per private key in ~/.ssh, scanned once.
#
# The three checks below used to walk the directory separately and call
# ssh-keygen from inside their own loops, so the same key was read three times
# and the answers only agreed by coincidence. They now render this.
#
#   name|type|has_passphrase|has_pub|perms
_ssh_scan() {
	[[ -d "$SSH_DIR" ]] || return 0
	local key key_name key_type has_passphrase has_pub perms
	for key in "$SSH_DIR"/id_*; do
		[[ -f "$key" ]] || continue
		[[ "$key" == *.pub ]] && continue

		key_name=$(basename "$key")

		# ssh-keygen succeeds with an empty passphrase only when there is none.
		has_passphrase=1
		ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1 && has_passphrase=0

		has_pub=0
		key_type="?"
		if [[ -f "${key}.pub" ]]; then
			has_pub=1
			key_type=$(ssh-keygen -l -f "${key}.pub" 2>/dev/null | awk '{print $NF}' || echo "?")
		fi

		perms=$(stat -f %A "$key" 2>/dev/null || echo "000")

		printf '%s|%s|%s|%s|%s\n' \
			"$key_name" "$key_type" "$has_passphrase" "$has_pub" "$perms"
	done
}

# ssh-keygen prints the type parenthesised, "(ED25519)". The table has always
# shown it that way; JSON should not.
_ssh_bare_type() {
	local type="$1"
	type="${type#(}"
	printf '%s' "${type%)}"
}

_ssh_json_report() {
	local dir_present=false dir_perms="000"
	if [[ -d "$SSH_DIR" ]]; then
		dir_present=true
		dir_perms=$(stat -f %A "$SSH_DIR" 2>/dev/null || echo "000")
	fi

	printf '{"ssh_dir_present":%s,"ssh_dir_perms":%s,"keys":[' \
		"$dir_present" "$(rcc_json_string "$dir_perms")"

	local first=1 name type has_passphrase has_pub perms
	while IFS='|' read -r name type has_passphrase has_pub perms; do
		[[ -z "$name" ]] && continue
		[[ $first -eq 0 ]] && printf ','
		first=0
		printf '{"name":%s,"type":%s,"passphrase":%s,"public_key":%s,"perms":%s,"perms_ok":%s}' \
			"$(rcc_json_string "$name")" \
			"$(rcc_json_string "$(_ssh_bare_type "$type")")" \
			"$([[ "$has_passphrase" -eq 1 ]] && echo true || echo false)" \
			"$([[ "$has_pub" -eq 1 ]] && echo true || echo false)" \
			"$(rcc_json_string "$perms")" \
			"$([[ "$perms" == "600" ]] && echo true || echo false)"
	done < <(_ssh_scan)

	printf ']}\n'
}

check_unprotected_keys() {
	print_section_header "Unprotected Keys"
	print_table_header "Key|Type|Status" 30 15 15

	local found=0 name type has_passphrase
	while IFS='|' read -r name type has_passphrase _ _; do
		[[ -z "$name" ]] && continue
		[[ "$has_passphrase" -eq 1 ]] && continue
		print_table_row "$name|$type|${YELLOW}NO PASSPHRASE${NC}" 30 15 15
		((found++)) || true
	done < <(_ssh_scan)

	if [[ $found -eq 0 ]]; then
		print_table_row "None|All protected|${GRAY}OK${NC}" 30 15 15
	fi
}

check_orphan_keys() {
	print_section_header "Orphan Keys"
	print_table_header "Key|Status" 30 15

	local found=0 name has_pub
	while IFS='|' read -r name _ _ has_pub _; do
		[[ -z "$name" ]] && continue
		[[ "$has_pub" -eq 1 ]] && continue
		print_table_row "$name|${YELLOW}No .pub file${NC}" 30 15
		((found++)) || true
	done < <(_ssh_scan)

	if [[ $found -eq 0 ]]; then
		print_table_row "None|${GRAY}OK${NC}" 30 15
	fi
}

check_key_permissions() {
	print_section_header "Key Permissions"
	print_table_header "Key|Perms|Status" 30 10 15

	local name perms
	while IFS='|' read -r name _ _ _ perms; do
		[[ -z "$name" ]] && continue
		if [[ "$perms" != "600" ]]; then
			print_table_row "$name|$perms|${RED}Should be 600${NC}" 30 10 15
		else
			print_table_row "$name|$perms|${GRAY}OK${NC}" 30 10 15
		fi
	done < <(_ssh_scan)
}

main() {
	if [[ "$JSON_OUTPUT" == "true" ]]; then
		_ssh_json_report
		return 0
	fi

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