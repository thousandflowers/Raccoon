#!/bin/bash
# build-standalone.sh — produce a single self-contained `rcc` file.
#
# The output is one runnable script: a small bootstrap followed by a base64 tar
# payload of the whole Bash tool (dispatcher + lib/ + bin/*.sh + completions +
# man). On first run it extracts to a versioned cache and execs the real
# dispatcher — no git, no repo clone. The compiled TUI binary (bin/rcc-ui) is
# deliberately NOT bundled: the single file is for CLI use ("download and run
# ./rcc audit"); the interactive menu still wants the Homebrew/curl install.
#
# The source stays fully inspectable in the repo and inside the artifact:
#   line=$(awk '/^__RCC_PAYLOAD__$/{print NR+1; exit}' rcc); tail -n +"$line" rcc | base64 -d | tar tzf -
#
# Usage: tools/build-standalone.sh [OUTPUT]   (default: dist/rcc)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUTPUT="${1:-dist/rcc}"
VERSION="$(cat VERSION 2>/dev/null || echo '0.0.0')"

# Runtime files the dispatcher needs. bin/*.sh are the commands; bin/rcc-ui (the
# compiled binary) is skipped on purpose.
PAYLOAD_FILES=(rcc VERSION)
[[ -d lib ]] && PAYLOAD_FILES+=(lib)
[[ -d completions ]] && PAYLOAD_FILES+=(completions)
[[ -d man ]] && PAYLOAD_FILES+=(man)
while IFS= read -r f; do PAYLOAD_FILES+=("$f"); done < <(find bin -name '*.sh' | sort)

mkdir -p "$(dirname "$OUTPUT")"

# 1. Bootstrap header (VERSION baked in).
cat > "$OUTPUT" <<BOOTSTRAP
#!/bin/bash
# Raccoon — single-file self-contained build (v${VERSION}).
# Download, chmod +x, run. Embeds the full Bash tool; extracts to a versioned
# cache on first run, then execs the real dispatcher. No git, no repo clone.
# Inspect the embedded source:  tail -n +<payload-line> "\$0" | base64 -d | tar tzf -
set -euo pipefail
RCC_BUNDLE_VERSION="${VERSION}"
RCC_CACHE="\${RCC_BUNDLE_CACHE:-\${TMPDIR:-/tmp}/raccoon-bundle-\${RCC_BUNDLE_VERSION}}"
if [[ ! -x "\$RCC_CACHE/rcc" ]]; then
	self="\$(readlink -f "\$0" 2>/dev/null || echo "\$0")"
	mkdir -p "\$RCC_CACHE"
	line="\$(awk '/^__RCC_PAYLOAD__\$/ { print NR + 1; exit }' "\$self")"
	tail -n "+\${line}" "\$self" | base64 -d | tar xzf - -C "\$RCC_CACHE"
fi
exec "\$RCC_CACHE/rcc" "\$@"
__RCC_PAYLOAD__
BOOTSTRAP

# 2. Append the base64 tar payload after the marker.
tar czf - "${PAYLOAD_FILES[@]}" | base64 >> "$OUTPUT"

chmod +x "$OUTPUT"

bytes="$(wc -c < "$OUTPUT" | tr -d ' ')"
echo "Built $OUTPUT (v${VERSION}, ${bytes} bytes, ${#PAYLOAD_FILES[@]} payload entries)"
