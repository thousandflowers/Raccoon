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

# The keychains the user's search list holds, one path per line. This is what
# `security find-certificate` reads when given no keychain, so listing anything
# else as a source would be a claim, not a measurement. The old list named
# /System/Library/Keychains/SystemRoot.keychain, a file that does not exist.
_certs_keychains() {
	{
		security list-keychains -d user 2>/dev/null
		security list-keychains -d system 2>/dev/null
	} | sed -n 's/^[[:space:]]*"\(.*\)"$/\1/p' | awk '!seen[$0]++'
}

# The scan, once. Both the table and --json read the same lines, tab-separated:
# sha256, keychain, name, issuer, notAfter, status, self_signed — and a final
# SUMMARY: row.
#
# Every certificate carries the keychain it came from and its SHA-256, because
# a name is not an address: `security delete-certificate -c NAME` takes the
# first match, and on this Mac the expired WWDR root's name also belongs to a
# valid one. Names come from the RFC 2253 form of the subject so they do not
# change with whichever openssl is first on PATH. Expiry is compared in UTC to
# the second: a certificate with an hour left is expiring, not expired.
_certs_scan() {
	python3 - "$EXPIRING_WINDOW" "$@" <<'PY'
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

window = timedelta(days=int(sys.argv[1]))
keychains = sys.argv[2:]
now = datetime.now(timezone.utc)


def rdn(field, dn):
    # RFC 2253: comma-separated, a comma inside a value escaped with a backslash.
    for part in re.split(r'(?<!\\),', dn):
        key, _, value = part.partition('=')
        if key.strip() == field:
            return re.sub(r'\\(.)', r'\1', value.strip())
    return ''


def name_of(dn):
    return rdn('CN', dn) or rdn('OU', dn) or rdn('O', dn) or dn


def not_checked(why):
    sys.stderr.write('Not checked: ' + why + '\n')
    sys.exit(3)


counts = dict(total=0, valid=0, expiring=0, expired=0, self_signed=0)
for keychain in keychains:
    listing = subprocess.run(
        ['security', 'find-certificate', '-a', '-p', '-Z', keychain],
        capture_output=True, text=True)
    if listing.returncode != 0:
        not_checked(f'could not read {keychain}: {listing.stderr.strip()}')
    for block in listing.stdout.split('SHA-256 hash: ')[1:]:
        sha256 = block.split('\n', 1)[0].strip()
        start = block.find('-----BEGIN CERTIFICATE-----')
        if start < 0:
            continue
        x509 = subprocess.run(
            ['openssl', 'x509', '-noout', '-subject', '-issuer', '-enddate',
             '-nameopt', 'RFC2253'],
            input=block[start:], capture_output=True, text=True)
        if x509.returncode != 0:
            not_checked(f'openssl could not read a certificate in {keychain}: '
                        f'{x509.stderr.strip()}')
        fields = {}
        for line in x509.stdout.splitlines():
            key, _, value = line.partition('=')
            fields[key.strip()] = value.strip()
        end = fields.get('notAfter', '')
        try:
            expires = datetime.strptime(end.replace(' GMT', ''),
                                        '%b %d %H:%M:%S %Y')
        except ValueError:
            not_checked(f'unreadable expiry {end!r} in {keychain}')
        remaining = expires.replace(tzinfo=timezone.utc) - now
        if remaining < timedelta(0):
            status = 'expired'
        elif remaining <= window:
            status = 'expiring'
        else:
            status = 'valid'
        subject, issuer = fields.get('subject', ''), fields.get('issuer', '')
        self_signed = subject == issuer
        counts['total'] += 1
        counts[status] += 1
        counts['self_signed'] += self_signed
        print('\t'.join([sha256, keychain, name_of(subject), name_of(issuer),
                         end, status, 'yes' if self_signed else 'no']))
print('SUMMARY:%d|%d|%d|%d|%d' % (counts['total'], counts['valid'],
                                   counts['expiring'], counts['expired'],
                                   counts['self_signed']))
PY
}

# Which rows the table shows. With no filter, all of them; --expired keeps the
# expired ones, --expiring N the ones inside the window. The old rule for
# --expiring hid only the expired rows, so it listed every valid certificate as
# if it were about to lapse while --json, with the same flag, said 0.
_certs_row_shown() {
	local status="$1"
	if [[ "$SHOW_EXPIRED" != true && $SHOW_EXPIRING -eq 0 ]]; then
		return 0
	fi
	[[ "$SHOW_EXPIRED" == true && "$status" == "expired" ]] && return 0
	[[ $SHOW_EXPIRING -gt 0 && "$status" == "expiring" ]] && return 0
	return 1
}

_json_report() {
	local details summary sha kc cn issuer end status self first=1
	local keychains=()
	while IFS= read -r kc; do
		[[ -n "$kc" ]] && keychains+=("$kc")
	done < <(_certs_keychains)
	details=$(_certs_scan ${keychains[@]+"${keychains[@]}"})
	summary=$(printf '%s\n' "$details" | grep "SUMMARY:" | sed 's/^SUMMARY://')

	printf '{\n'
	printf '  "counts": {"total": %s, "valid": %s, "expiring": %s, "expired": %s, "self_signed": %s},\n' \
		"$(rcc_json_number "$(printf '%s' "$summary" | cut -d'|' -f1)")" \
		"$(rcc_json_number "$(printf '%s' "$summary" | cut -d'|' -f2)")" \
		"$(rcc_json_number "$(printf '%s' "$summary" | cut -d'|' -f3)")" \
		"$(rcc_json_number "$(printf '%s' "$summary" | cut -d'|' -f4)")" \
		"$(rcc_json_number "$(printf '%s' "$summary" | cut -d'|' -f5)")"
	printf '  "expiring_window_days": %s,\n' "$EXPIRING_WINDOW"

	printf '  "certificates": ['
	while IFS=$'\t' read -r sha kc cn issuer end status self; do
		[[ -z "$sha" ]] && continue
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    {"name": %s, "issuer": %s, "expires": %s, "status": %s, "self_signed": %s, "keychain": %s, "sha256": %s}' \
			"$(rcc_json_string "$cn")" "$(rcc_json_string "$issuer")" \
			"$(rcc_json_string "$end")" "$(rcc_json_string "$status")" \
			"$([[ "$self" == "yes" ]] && echo true || echo false)" \
			"$(rcc_json_string "$kc")" "$(rcc_json_string "$sha")"
	done < <(printf '%s\n' "$details" | grep -v "SUMMARY:")
	[[ $first -eq 1 ]] || printf '\n  '
	printf '],\n'

	printf '  "keychains": ['
	first=1
	for kc in ${keychains[@]+"${keychains[@]}"}; do
		[[ $first -eq 1 ]] || printf ','
		first=0
		printf '\n    %s' "$(rcc_json_string "$kc")"
	done
	[[ $first -eq 1 ]] || printf '\n  '
	printf ']\n}\n'
}

main() {
	rcc_require_tools security openssl python3
	if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
		_json_report
		return 0
	fi
	print_section_header "Certificates Status"

	print_step 1 3 "Keychain Certificates"

	local kc
	local keychains=()
	while IFS= read -r kc; do
		[[ -n "$kc" ]] && keychains+=("$kc")
	done < <(_certs_keychains)

	local details
	details=$(_certs_scan ${keychains[@]+"${keychains[@]}"})
	
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
			while IFS=$'\t' read -r _ _ cn issuer end_date status _; do
				if _certs_row_shown "$status"; then
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
	print_step 3 3 "Keychains Searched"
	for kc in ${keychains[@]+"${keychains[@]}"}; do
		print_info "$kc"
	done
	[[ ${#keychains[@]} -gt 0 ]] || print_warning "No keychain in the search list"
	print_success "${#keychains[@]} keychains searched. System Roots are trusted by macOS and left out."
	
	echo ""
	echo "${GREEN}${ICON_SUCCESS} Completed${NC}"
}

main "$@"