#!/bin/bash
# demo-audit.sh: per la generazione GIF — bypassa sudo ed esegue audit completo
# Patch temporanea di audit.sh (non modifica l'originale)
WRAPPER_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
RACCOON_DIR="$(cd "$WRAPPER_DIR/../.." && pwd)"

TMP_AUDIT=$(mktemp /tmp/rcc-audit-demo.XXXXXX)
trap 'rm -f "$TMP_AUDIT"' EXIT

# Patch: fixa SCRIPT_DIR al percorso reale, disabilita sudo
sed "s|^SCRIPT_DIR=\"\$(cd \"\$(dirname \"\$SCRIPT_PATH\")\" \&\& pwd)\"|SCRIPT_DIR=\"${RACCOON_DIR}/bin\"|" \
  "${RACCOON_DIR}/bin/audit.sh" | \
sed 's/^SUDO_AVAILABLE=true/SUDO_AVAILABLE=false/' | \
sed '/^_sudo() {/,/^}$/c\
_sudo() { return 1; }' > "$TMP_AUDIT"

chmod +x "$TMP_AUDIT"

# Sanitize for the GIF: the real "DNS Servers" value is an IPv6 link-local
# address whose host part is derived from this Mac's MAC address, and it is
# wide enough to overflow the table border. A scutil shim on PATH swaps it for
# a public resolver, so the frame carries no machine identifier.
# ponytail: shim only rewrites nameserver lines; everything else passes through.
SHIM_DIR=$(mktemp -d /tmp/rcc-audit-shim.XXXXXX)
trap 'rm -f "$TMP_AUDIT"; rm -rf "$SHIM_DIR"' EXIT
cat > "$SHIM_DIR/scutil" <<'SHIM'
#!/bin/bash
/usr/sbin/scutil "$@" | sed -E 's/(nameserver\[[0-9]+\] : ).*/\11.1.1.1/'
SHIM

# `softwareupdate -l` reaches Apple's servers and has taken >7 minutes here on
# a cold cache, which makes the recording hang rather than fail. The demo does
# not exercise that network path, so it answers with the same sentinel string
# the check looks for ("No new software available").
cat > "$SHIM_DIR/softwareupdate" <<'SHIM'
#!/bin/bash
echo "No new software available."
SHIM

# The sed patches above only touch bin/audit.sh, but _ensure_sudo lives in
# lib/core/common.sh and still runs `sudo -v`. With no cached sudo timestamp
# that blocks on a password prompt forever, which is what made the recording
# hang for minutes at a time. Failing fast selects the same no-sudo path the
# patches already intend.
cat > "$SHIM_DIR/sudo" <<'SHIM'
#!/bin/bash
# Answer the credential probes only, so ensure_sudo returns 0 and the deep
# scan is not skipped. Every real invocation fails, matching the patched
# _sudo() above — no command ever actually runs with privilege.
case "$*" in
	"-n true" | "-v") exit 0 ;;
esac
exit 1
SHIM

chmod +x "$SHIM_DIR/scutil" "$SHIM_DIR/softwareupdate" "$SHIM_DIR/sudo"
export PATH="$SHIM_DIR:$PATH"

# Not exec: exec replaces the shell and discards the EXIT trap, so the temp
# script and shim dir would survive every demo run.
"$TMP_AUDIT" "$@"
exit $?
