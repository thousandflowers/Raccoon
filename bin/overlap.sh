#!/bin/bash

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

show_overlap_help() {
	print_help_header "overlap" "Map the PATH to the package manager behind each entry" "[--json]"
	echo "  --json          Output in JSON format"
	echo ""
	echo "  Read-only. Nothing is executed, moved or removed: versions are"
	echo "  deliberately absent because they belong to manager metadata, never"
	echo "  to running the binary. Shims (mise, asdf, pyenv, rbenv, nvm, volta)"
	echo "  are a category of their own — per-project shadowing is their job,"
	echo "  not a problem."
	echo ""
	echo "  ~/.local/bin is reported as pipx, but also collects scripts dropped"
	echo "  there by curl installers. Apple's own binaries report as system:"
	echo "  they sit under SIP, so no manager installed them and none can"
	echo "  update or remove them."
	echo ""
	echo "  One row per PATH entry, not per executable. Broken and circular"
	echo "  symlinks are on the map too, and the same name appearing under two"
	echo "  managers stays two rows."
	echo ""
}

JSON_OUTPUT=false

for arg in "$@"; do
	case "$arg" in
	--help | -h)
		show_overlap_help
		exit 0
		;;
	--json)
		JSON_OUTPUT=true
		;;
	*)
		echo "Unknown option: $arg"
		echo "Usage: rcc overlap [--json]"
		exit 1
		;;
	esac
done

# =====================================================================
# Attribution table
# =====================================================================

# One "prefix|manager" rule per line. The system roots are read through
# $RCC_OVERLAP_ROOT (empty in production) so the whole table can be pointed at
# a fixture tree — that is what keeps the tests off this machine's filesystem.
_overlap_rules() {
	local root="${RCC_OVERLAP_ROOT:-}"
	local npm_prefix cargo_home go_bin

	npm_prefix="${RCC_OVERLAP_NPM_PREFIX:-}"
	if [[ -z "$npm_prefix" ]] && command -v npm > /dev/null 2>&1; then
		# Manager metadata, not the scanned binary: npm is the one manager
		# whose global prefix is not at a predictable path.
		npm_prefix="$(npm config get prefix 2>/dev/null || true)"
	fi
	if [[ -n "$npm_prefix" ]]; then
		printf '%s|npm\n' "${npm_prefix}/lib/node_modules"
	fi

	cargo_home="${CARGO_HOME:-$HOME/.cargo}"
	go_bin="${GOBIN:-${GOPATH:-$HOME/go}/bin}"

	printf '%s|brew\n' "${root}/opt/homebrew/Cellar"
	printf '%s|brew\n' "${root}/opt/homebrew/Caskroom"
	printf '%s|brew\n' "${root}/usr/local/Cellar"
	printf '%s|brew\n' "${root}/usr/local/Caskroom"
	printf '%s|cargo\n' "${cargo_home}/bin"
	printf '%s|go\n' "$go_bin"
	printf '%s|macports\n' "${root}/opt/local"
	printf '%s|nix\n' "${root}/nix/store"
	printf '%s|nix\n' "$HOME/.nix-profile"
	printf '%s|pipx\n' "$HOME/.local/bin"

	# Last, so a manager prefix that nests inside one of these still wins.
	# Apple's own binaries live under SIP: no manager installed them, none can
	# update or remove them. Leaving them in "orphan" would bury the handful of
	# genuinely unmanaged binaries under a thousand rows that mean nothing.
	printf '%s|system\n' "${root}/usr/bin"
	printf '%s|system\n' "${root}/usr/sbin"
	printf '%s|system\n' "${root}/usr/libexec"
	printf '%s|system\n' "${root}/bin"
	printf '%s|system\n' "${root}/sbin"
	# Fifty of /usr/bin's entries are symlinks into /System/Library —
	# qlmanage, fontrestore, the acfs tools — and were read as orphans because
	# the rule matched the link's target, not the link. Same for the developer
	# tools: what xcode-select installs is Apple's, whichever bundle holds it.
	printf '%s|system\n' "${root}/System/Library"
	printf '%s|xcode\n' "${root}/Library/Developer/CommandLineTools"
	printf '%s|xcode\n' "${root}/Applications/Xcode.app"
	# MacTeX ships tlmgr, which is the manager for everything under it.
	printf '%s|tlmgr\n' "${root}/Library/TeX"
	printf '%s|tlmgr\n' "${root}/usr/local/texlive"
}

# Version managers shadow binaries per project on purpose. They are matched
# before the rules above and reported as their own category, never as an
# overlap: calling mise an overlap is the false positive that would sink this.
# The patterns are directory-shaped ("/share/mise/", not "/mise/") so that a
# version manager installed by a package manager — brew's own mise formula
# lives in Cellar/mise/... — is still attributed to the manager that shipped
# it, and only the tools it shadows read as shims.
_overlap_shim_patterns() {
	printf '%s\n' \
		'/shims/' \
		'/.asdf/' \
		'/.pyenv/' \
		'/.rbenv/' \
		'/.nvm/' \
		'/.volta/' \
		'/share/mise/'
}

# =====================================================================
# Path resolution (bash 3.2, no readlink -f: that flag is GNU)
# =====================================================================

# Fold "." and ".." lexically. Homebrew's bin entries are relative links like
# ../Cellar/rg/14.1.0/bin/rg — left unfolded they match no prefix at all and
# every brew binary would read as an orphan.
_overlap_normalize() {
	local rest="$1"
	local out=""
	local part

	while [[ -n "$rest" ]]; do
		part="${rest%%/*}"
		if [[ "$part" == "$rest" ]]; then
			rest=""
		else
			rest="${rest#*/}"
		fi
		case "$part" in
		"" | ".") ;;
		"..") out="${out%/*}" ;;
		*) out="$out/$part" ;;
		esac
	done

	printf '%s\n' "${out:-/}"
}

# Walk a symlink chain by hand. Result lands in $OVERLAP_RESOLVED.
OVERLAP_RESOLVED=""
_overlap_resolve() {
	local path="$1"
	local hops=0
	local target dir

	while [[ -L "$path" ]]; do
		hops=$((hops + 1))
		# ponytail: 40 is far past any real install chain; this cap is the
		# only thing standing between a symlink cycle and a hang.
		if [[ $hops -gt 40 ]]; then
			break
		fi
		target="$(readlink "$path" 2>/dev/null)" || break
		[[ -z "$target" ]] && break
		case "$target" in
		/*) path="$target" ;;
		*)
			dir="${path%/*}"
			[[ "$dir" == "$path" ]] && dir="."
			path="$dir/$target"
			;;
		esac
		case "$path" in
		*/../* | */./* | */.. | */.) path="$(_overlap_normalize "$path")" ;;
		esac
	done

	OVERLAP_RESOLVED="$path"
}

# Attribute a resolved path to a manager. Result lands in $OVERLAP_MANAGER.
OVERLAP_MANAGER=""
_overlap_classify() {
	local entry="$1"
	local resolved="$2"
	local pattern rule prefix

	while IFS= read -r pattern; do
		[[ -z "$pattern" ]] && continue
		case "$entry" in *"$pattern"*)
			OVERLAP_MANAGER="shim"
			return 0
			;;
		esac
		case "$resolved" in *"$pattern"*)
			OVERLAP_MANAGER="shim"
			return 0
			;;
		esac
	done <<< "$OVERLAP_SHIMS"

	while IFS= read -r rule; do
		[[ -z "$rule" ]] && continue
		prefix="${rule%|*}"
		[[ -z "$prefix" ]] && continue
		case "$resolved/" in "$prefix"/*)
			OVERLAP_MANAGER="${rule##*|}"
			return 0
			;;
		esac
	done <<< "$OVERLAP_RULES"

	OVERLAP_MANAGER="orphan"
}

# =====================================================================
# Scan
# =====================================================================

# Emits one tab-separated record per PATH entry: name, path, resolved, manager.
# Every PATH entry stays its own record even when two managers ship the same
# basename — that repetition is the shadowing signal, and collapsing it here
# would throw the data away.
#
# ponytail: tab-separated, so a filename containing a tab or a newline would
# split into a broken record. Nothing in a package manager's bin directory is
# named like that; switch to NUL-separated records if one ever is.
_overlap_scan() {
	local target_path="${RCC_OVERLAP_PATH-$PATH}"
	local seen dir entry name

	seen=$'\n'
	while IFS= read -r -d ':' dir; do
		[[ -z "$dir" ]] && continue
		# A relative PATH entry cannot be attributed to a manager, and
		# resolving it against the cwd would be a guess.
		case "$dir" in
		/*) ;;
		*) continue ;;
		esac
		# A trailing slash makes the same directory look like a new one.
		while [[ "$dir" == */ && "$dir" != "/" ]]; do
			dir="${dir%/}"
		done
		# Directories are de-duplicated; the executables inside them are not.
		case "$seen" in *$'\n'"$dir"$'\n'*) continue ;; esac
		seen="${seen}${dir}"$'\n'
		# Missing, unreadable or non-traversable: skipped in silence.
		[[ -d "$dir" && -r "$dir" && -x "$dir" ]] || continue

		for entry in "$dir"/*; do
			[[ -e "$entry" || -L "$entry" ]] || continue
			[[ -d "$entry" ]] && continue
			# A dangling symlink is not -x but still belongs on the map.
			[[ -x "$entry" || -L "$entry" ]] || continue

			name="${entry##*/}"
			_overlap_resolve "$entry"
			_overlap_classify "$entry" "$OVERLAP_RESOLVED"
			printf '%s\t%s\t%s\t%s\n' "$name" "$entry" "$OVERLAP_RESOLVED" "$OVERLAP_MANAGER"
		done
	done <<< "${target_path}:"
}

# =====================================================================
# Output
# =====================================================================

_overlap_json() {
	awk -F '\t' '
		# Escaped one character at a time on purpose: what a backslash in a
		# gsub() replacement means differs between awk implementations, so
		# gsub() here would emit different JSON on macOS awk and on gawk.
		function esc(s,   out, i, c) {
			out = ""
			for (i = 1; i <= length(s); i++) {
				c = substr(s, i, 1)
				if (c == "\\" || c == "\"") out = out "\\" c
				else out = out c
			}
			return out
		}
		BEGIN { n = 0 }
		{
			if (n++) printf ",\n"; else printf "[\n"
			printf "    {\"name\": \"%s\", \"path\": \"%s\", \"resolved\": \"%s\", \"manager\": \"%s\"}", esc($1), esc($2), esc($3), esc($4)
		}
		END { if (n) printf "\n]\n"; else printf "[]\n" }
	'
}

# Trim from the left, keeping the tail: on a resolved path the manager
# directory and the binary name are the informative end. ASCII "..." on
# purpose — print_table_row counts widths in bytes under LC_ALL=C.
_overlap_ellipsize() {
	local text="$1"
	local width="$2"

	if [[ ${#text} -le $width ]]; then
		printf '%s\n' "$text"
		return 0
	fi
	printf '...%s\n' "${text: -$((width - 3))}"
}

_overlap_table() {
	local name path resolved manager

	print_section_header "PATH Overlap"
	print_table_header "NAME|PATH|RESOLVED|MANAGER" 18 34 44 9

	while IFS=$'\t' read -r name path resolved manager; do
		name="$(_overlap_ellipsize "$name" 18)"
		path="$(_overlap_ellipsize "$path" 34)"
		resolved="$(_overlap_ellipsize "$resolved" 44)"
		print_table_row "$name|$path|$resolved|$manager" 18 34 44 9
	done

	echo ""
	print_success "Completed"
}

main() {
	OVERLAP_RULES="$(_overlap_rules)"
	OVERLAP_SHIMS="$(_overlap_shim_patterns)"

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		_overlap_scan | _overlap_json
		exit 0
	fi

	_overlap_scan | _overlap_table
}

main "$@"
