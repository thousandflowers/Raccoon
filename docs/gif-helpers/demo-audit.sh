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
exec "$TMP_AUDIT" "$@"
