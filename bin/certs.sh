#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_certs_help() {
	echo "Usage: rcc certs [options]"
	echo ""
	echo "Show SSL certificates in keychain"
	echo ""
	echo "Options:"
	echo "  --expired       Show only expired certificates"
	echo "  --expiring N   Show certificates expiring within N days"
	echo "  --detail        Show full certificate details"
	echo "  --json          Output in JSON format"
	echo "  --help, -h      Show this help"
}

# shellcheck disable=SC2034
JSON_OUTPUT=false
SHOW_EXPIRED=false
SHOW_EXPIRING=0
EXPIRING_WINDOW=30
SHOW_DETAIL=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--help | -h)
		show_certs_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	--expired)
		SHOW_EXPIRED=true
		;;
	--expiring)
		# Optional numeric arg: "--expiring 7" -> within 7 days; bare --expiring -> 30.
		if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
			SHOW_EXPIRING="$2"
			EXPIRING_WINDOW="$2"
			shift
		else
			SHOW_EXPIRING=30
		fi
		;;
	--detail)
		SHOW_DETAIL=true
		;;
	*)
		;;
	esac
	shift
done

# The scan, once. Both the table and --json read the same lines:
# cn|issuer|notAfter|status|self_signed, and a final SUMMARY: row.
_certs_scan() {
	security find-certificate -a -p 2>/dev/null | python3 -c "
import sys
import subprocess
from datetime import datetime

data = sys.stdin.read()
certs = data.split('-----BEGIN CERTIFICATE-----')
certs = [c for c in certs if c.strip()]

total = 0
valid = 0
expiring = 0
expired = 0
selfsigned = 0
now = datetime.now()

for cert in certs:
    pem = '-----BEGIN CERTIFICATE-----' + cert
    try:
        proc = subprocess.Popen(['openssl', 'x509', '-noout', '-subject', '-issuer', '-enddate'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, _ = proc.communicate(input=pem.encode())
        lines = out.decode().strip().split('\n')
        subject = ''
        issuer = ''
        enddate = ''
        for l in lines:
            if l.startswith('subject='):
                subject = l.replace('subject=', '')
            elif l.startswith('issuer='):
                issuer = l.replace('issuer=', '')
            elif l.startswith('notAfter='):
                enddate = l.replace('notAfter=', '')
        
        if not enddate:
            continue
            
        try:
            exp = datetime.strptime(enddate.replace(' GMT', ''), '%b %d %H:%M:%S %Y')
        except:
            continue
            
        diff = (exp - now).days
        
        if diff < 0:
            status = 'expired'
        elif diff <= ${EXPIRING_WINDOW}:
            status = 'expiring'
        else:
            status = 'valid'
            
        cn = subject.split('CN=')[-1].split('/')[0] if 'CN=' in subject else subject
        issuer_cn = issuer.split('CN=')[-1].split('/')[0] if 'CN=' in issuer else issuer
        is_self = 'yes' if cn == issuer_cn else 'no'
        
        print(f'{cn}|{issuer_cn}|{enddate}|{status}|{is_self}')
        
        total += 1
        if status == 'valid':
            valid += 1
        elif status == 'expiring':
            expiring += 1
        elif status == 'expired':
            expired += 1
        if is_self == 'yes':
            selfsigned += 1
    except:
        pass

print(f'SUMMARY:{total}|{valid}|{expiring}|{expired}|{selfsigned}')
"
}

_json_report() {
	local details summary cn issuer end status self first=1
	details=$(_certs_scan)
	summary=$(printf '%s\n' "$details" | grep "SUMMARY:" | sed 's/^SUMMARY://')

	printf '{\n'
	printf '  "counts": {"total": %s, "valid": %s, "expiring": %s, "expired": %s, "self_signed": %s},\n' \
		"$(printf '%s' "$summary" | cut -d'|' -f1)" \
		"$(printf '%s' "$summary" | cut -d'|' -f2)" \
		"$(printf '%s' "$summary" | cut -d'|' -f3)" \
		"$(printf '%s' "$summary" | cut -d'|' -f4)" \
		"$(printf '%s' "$summary" | cut -d'|' -f5)"
	printf '  "expiring_window_days": %s,\n' "$EXPIRING_WINDOW"

	printf '  "certificates": ['
	while IFS='|' read -r cn issuer end status self; do
		[[ -z "$cn" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "issuer": %s, "expires": %s, "status": %s, "self_signed": %s}' \
			"$(rcc_json_string "$cn")" "$(rcc_json_string "$issuer")" \
			"$(rcc_json_string "$end")" "$(rcc_json_string "$status")" \
			"$([[ "$self" == "yes" ]] && echo true || echo false)"
	done < <(printf '%s\n' "$details" | grep -v "SUMMARY:")
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "keychains": [\n    %s,\n    %s,\n    %s\n  ]\n}\n' \
		"$(rcc_json_string "$HOME/Library/Keychains/login.keychain-db")" \
		"$(rcc_json_string "/Library/Keychains/System.keychain")" \
		"$(rcc_json_string "/System/Library/Keychains/SystemRoot.keychain")"
}

main() {
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	print_section_header "Certificates Status"
	
	print_step 1 3 "User Keychain Certificates"
	
	local details
	details=$(_certs_scan)
	
	local summary
	# Strip the "SUMMARY:" prefix so cut -f1 is `total`, not "SUMMARY:total"
	# (the prefix used to merge with field 1, shifting every column by one).
	summary=$(echo "$details" | grep "SUMMARY:" | sed 's/^SUMMARY://')
	local cert_lines
	cert_lines=$(echo "$details" | grep -v "SUMMARY:")
	
	local total valid expiring expired selfsigned
	total=0
	valid=0
	expiring=0
	expired=0
	selfsigned=0
	
	if [[ -n "$summary" ]]; then
		total=$(echo "$summary" | cut -d'|' -f1)
		valid=$(echo "$summary" | cut -d'|' -f2)
		expiring=$(echo "$summary" | cut -d'|' -f3)
		expired=$(echo "$summary" | cut -d'|' -f4)
		selfsigned=$(echo "$summary" | cut -d'|' -f5)
	fi
	
	printf "%-12s %12s %12s %12s %12s\n" "Total" "Valid" "Expiring" "Expired" "Self-Signed"
	echo "${GRAY}────────────────────────────────────────────────────────────────────────────${NC}"
	printf "%-12s %12s %12s %12s %12s\n" "$total" "$valid" "$expiring" "$expired" "$selfsigned"
	echo "${GREEN}✓${NC}"
	
	if [[ "$SHOW_DETAIL" == true ]] || [[ "$SHOW_EXPIRED" == true ]] || [[ $SHOW_EXPIRING -gt 0 ]]; then
		echo ""
		print_step 2 3 "Certificate Details"
		
		if [[ -n "$cert_lines" ]]; then
			printf "%-35s %-18s %-12s %-10s\n" "Certificate" "Issuer" "Expires" "Status"
			print_info "────────────────────────────────────────────────────────────────────────"
			while IFS='|' read -r cn issuer end_date status _; do
				local show=true
				
				if [[ "$SHOW_EXPIRED" == true ]] && [[ "$status" != "expired" ]]; then
					show=false
				fi
				if [[ $SHOW_EXPIRING -gt 0 ]] && [[ "$status" == "expired" ]]; then
					show=false
				fi
				
				if [[ "$show" == true ]]; then
					local status_color
					case "$status" in
						valid) status_color="${GREEN}$status${NC}" ;;
						expiring) status_color="${YELLOW}$status${NC}" ;;
						expired) status_color="${RED}$status${NC}" ;;
						*) status_color="$status" ;;
					esac
					printf "%-35s %-18s %-12s %-10s\n" "${cn:0:35}" "${issuer:0:18}" "$end_date" "$status_color"
				fi
			done <<< "$cert_lines"
		fi
		
		echo "${GREEN}✓${NC}"
	fi
	
	echo ""
	print_step 3 3 "Keychain Locations"
	print_info "$HOME/Library/Keychains/login.keychain-db"
	print_info "/Library/Keychains/System.keychain"
	print_info "/System/Library/Keychains/SystemRoot.keychain"
	print_success "Keychain locations listed"
	
	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"