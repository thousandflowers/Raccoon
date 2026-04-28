#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_certs_help() {
	echo "Usage: rcc certs [options]"
	echo ""
	echo "Show SSL certificates in keychain"
	echo ""
	echo "Options:"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_certs_help
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
	print_section_header "Certificates Status"

	echo "${GRAY}[1/4] System Keychain...${NC}"
	local sys_certs
	sys_certs=$(security find-certificate -a -p -s "/System/Library/Keychains/SystemRoot.keychain" 2>/dev/null | wc -l | xargs || echo "0")
	echo "  SystemRoot keychain: $sys_certs lines"
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[2/4] User Keychain...${NC}"
	local user_certs
	user_certs=$(security find-certificate -a -p 2>/dev/null | wc -l | xargs || echo "0")
	echo "  login.keychain: $user_certs lines"
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[3/4] Certificate Summary...${NC}"
	local total_certs
	total_certs=$user_certs
	echo "  Total entries: $total_certs"
	if [[ -n "$user_certs" && "$user_certs" != "0" ]]; then
		echo "  ${GRAY}Use security find-certificate to view details${NC}"
	else
		echo "  ${GRAY}No certificates found in user keychain${NC}"
	fi
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GRAY}[4/4] Keychain Locations...${NC}"
	echo "  ~/Library/Keychains/login.keychain-db"
	echo "  /Library/Keychains/SystemRoot.keychain"
	echo "${GREEN}✓${NC}"

	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"