#!/bin/bash
# changelog-section.sh: print the CHANGELOG section for one version.
#
# The release notes and the preflight that previews them both call this, so
# what you read before tagging is produced by the same code that runs at tag
# time. Two copies of this awk would defeat the point of the preview.
#
#   tools/changelog-section.sh 0.17.0
#   tools/changelog-section.sh 0.17.0 path/to/CHANGELOG.md
#
# Exit 1 with the list of headings it did find when the version has no section,
# which is what you need to see when the tag and the CHANGELOG disagree.
set -euo pipefail

version="${1:-}"
changelog="${2:-CHANGELOG.md}"

if [[ -z "$version" ]]; then
	echo "usage: changelog-section.sh <version> [changelog]" >&2
	exit 64
fi
if [[ ! -f "$changelog" ]]; then
	echo "ERROR: $changelog not found" >&2
	exit 1
fi

# The heading is matched as a literal prefix, not as a regex: a version number
# is mostly dots, and "0.17.0" as a pattern also matches "0917.0". The section
# runs to the next "## " heading, so it keeps its own ### subsections.
section=$(awk -v v="$version" '
	index($0, "## [" v "]") == 1 { found = 1; next }
	found && index($0, "## ") == 1 { exit }
	found { print }
' "$changelog" | awk 'NF { p = 1 } p' | awk '
	{ a[NR] = $0 }
	END {
		n = NR
		while (n > 0 && a[n] == "") n--
		for (i = 1; i <= n; i++) print a[i]
	}
')

if [[ -z "$section" ]]; then
	echo "ERROR: $changelog has no '## [$version]' section" >&2
	echo "Sections found:" >&2
	grep '^## ' "$changelog" >&2 || true
	exit 1
fi

printf '%s\n' "$section"
