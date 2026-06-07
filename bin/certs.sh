#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_certs_help() {
	print_help_header "certs" "SSL certificates in keychain" "[--json] [--expired] [--expiring N] [--detail]"
	echo "  --json          Output in JSON format"
	echo "  --expired       Show only expired certificates"
	echo "  --expiring N   Show certificates expiring within N days"
	echo "  --detail        Show detailed certificate info"
	echo ""
}

JSON_OUTPUT=false
SHOW_EXPIRED=false
SHOW_EXPIRING=0
SHOW_DETAIL=false

for arg in "$@"; do
	case "$arg" in
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
		SHOW_EXPIRING=30
		;;
	--detail)
		SHOW_DETAIL=true
		;;
	*)
		;;
	esac
done

main() {
	print_section_header "Certificates Status"
	
	print_step 1 4 "User Keychain Certificates"
	
	local details
	details=$(security find-certificate -a -p 2>/dev/null | python3 -c "
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
        elif diff <= 30:
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
")
	
	local summary
	summary=$(echo "$details" | grep "SUMMARY:")
	local cert_lines
	cert_lines=$(echo "$details" | grep -v "SUMMARY:")
	
	local total valid expiring expired selfsigned
	total=0
	valid=0
	expiring=0
	expired=0
	selfsigned=0
	
	if [[ -n "$summary" ]]; then
		total=$(echo "$summary" | cut -d'|' -f2)
		valid=$(echo "$summary" | cut -d'|' -f3)
		expiring=$(echo "$summary" | cut -d'|' -f4)
		expired=$(echo "$summary" | cut -d'|' -f5)
		selfsigned=$(echo "$summary" | cut -d'|' -f6)
	fi
	
	printf "%-12s %12s %12s %12s %12s\n" "Total" "Valid" "Expiring" "Expired" "Self-Signed"
	print_info "────────────────────────────────────────────────────────────────────────────"
	printf "%-12s %12s %12s %12s %12s\n" "$total" "$valid" "$expiring" "$expired" "$selfsigned"
	print_success "Keychain certificates scanned"
	
	if [[ "$SHOW_DETAIL" == true ]] || [[ "$SHOW_EXPIRED" == true ]] || [[ $SHOW_EXPIRING -gt 0 ]]; then
		echo ""
		print_step 2 4 "Certificate Details"
		
		if [[ -n "$cert_lines" ]]; then
			printf "%-35s %-18s %-12s %-10s\n" "Certificate" "Issuer" "Expires" "Status"
			print_info "────────────────────────────────────────────────────────────────────────"
			while IFS='|' read -r cn issuer end_date status is_self; do
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
		
		print_success "Certificate details listed"
	fi
	
	echo ""
	print_step 3 4 "Keychain Locations"
	print_info "~/Library/Keychains/login.keychain-db"
	print_info "/Library/Keychains/System.keychain"
	print_info "/System/Library/Keychains/SystemRoot.keychain"
	print_success "Keychain locations listed"
	
	echo ""
	print_success "Completed"
}

main "$@"