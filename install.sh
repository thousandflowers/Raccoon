#!/bin/bash

set -e

REPO_URL="https://github.com/thousandflowers/Raccoon.git"
INSTALL_DIR="${HOME}/.raccoon"
BIN_DIR=""
VERSION="unknown"

detect_bin_dir() {
	if [[ -w "/usr/local/bin" ]]; then
		echo "/usr/local/bin"
	elif [[ -w "/usr/local" ]]; then
		echo "/usr/local/bin"
	else
		echo "${HOME}/.local/bin"
	fi
}

# The version lives in the VERSION file — commands.sh only reads it, and has
# done since the formula started stamping the tag there. Grepping commands.sh
# for VERSION= matched its `VERSION="${VERSION:-dev}"` fallback and printed that
# line verbatim, so every curl install ended on "installed successfully
# (v${VERSION:-dev})".
get_version() {
	if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
		tr -d '[:space:]' < "${INSTALL_DIR}/VERSION"
	fi
}

# ─── The raccoon, while you wait ────────────────────────────────────────────
#
# `curl | bash` is where most people meet Raccoon, and it used to be six lines
# of prose. The animation is the same face the TUI draws, so what you install
# and what greets you are the same animal.
#
# Everything below degrades on purpose. A pipe, a CI log or a terminal that
# cannot move the cursor gets plain lines instead: `[[ -t 1 ]]` decides, and
# nothing here is required for the install to work.
ANIMATE=false
[[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && ANIMATE=true

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
	BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'
else
	BOLD=""; GREEN=""; NC=""
fi

# Four eye shapes, one per beat. The silhouette never changes: the ears and the
# mouth stay put and only the eyes move, which is the rule the TUI follows too.
RCC_EYES=("o.o" "-.-" "o.o" "^.^")

# One frame of the raccoon, with a caption to its right.
_rcc_frame() {
	local eyes="$1" caption="$2"
	printf '   %sn___n%s\n' "$BOLD" "$NC"
	printf '  %s[ %s ]%s  %s\n' "$BOLD" "$eyes" "$NC" "$caption"
	printf '   %s> ^ <%s\n' "$BOLD" "$NC"
}

# Draw the face once, then redraw it in place while a step runs. Without a tty
# the caption is printed once and the cursor is left alone.
_rcc_step() {
	local caption="$1"
	if [[ "$ANIMATE" != "true" ]]; then
		printf '  %s\n' "$caption"
		return 0
	fi
	local i
	for i in 0 1 2 3; do
		_rcc_frame "${RCC_EYES[$i]}" "$caption"
		sleep 0.08
		# Three lines up, to redraw over the face just printed.
		printf '\033[3A'
	done
	_rcc_frame "o.o" "$caption"
	printf '\033[3A'
}

# Leave the last frame on screen instead of scrolling past it.
_rcc_done() {
	_rcc_frame "^.^" "${GREEN}$1${NC}"
}

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
	printf '\n'
fi
_rcc_step "Installing Raccoon"

BIN_DIR=$(detect_bin_dir)
mkdir -p "${BIN_DIR}"

clone_repo() {
	# Shallow + partial + sparse: skip history, and never fetch or check out
	# docs/ (heavy GIFs) or tests/. Keeps ~/.raccoon small and fast to install.
	# Falls back to a plain shallow clone if git is too old for partial clone.
	if git clone --depth 1 --filter=blob:none --no-checkout "$REPO_URL" "${INSTALL_DIR}" 2>/dev/null; then
		cd "${INSTALL_DIR}"
		git sparse-checkout set --no-cone '/*' '!/docs/' '!/tests/' 2>/dev/null || true
		git checkout
	else
		git clone --depth 1 "$REPO_URL" "${INSTALL_DIR}"
	fi
}

if [[ ! -d "${INSTALL_DIR}" ]]; then
	_rcc_step "Cloning the repository"
	clone_repo
else
	_rcc_step "Updating your installation"
	cd "${INSTALL_DIR}" && git fetch --depth 1 origin main && git reset --hard origin/main
fi

VERSION=$(get_version)

ln -sf "${INSTALL_DIR}/rcc" "${BIN_DIR}/rcc"
_rcc_step "Linked rcc to ${BIN_DIR}"

MAN_DIR="${BIN_DIR}/../share/man/man1"
MAN_DIR="$(cd "$MAN_DIR" 2>/dev/null && pwd || echo "${BIN_DIR}/../share/man/man1")"
mkdir -p "${MAN_DIR}" 2>/dev/null
if [[ -d "${MAN_DIR}" ]]; then
	ln -sf "${INSTALL_DIR}/man/man1/rcc.1" "${MAN_DIR}/rcc.1"
	_rcc_step "Linked the man page"
fi

chmod +x "${INSTALL_DIR}/rcc"
chmod +x "${BIN_DIR}/rcc"

# Optional interactive TUI (bin/rcc-ui). It is no longer committed to the repo,
# so build it from source when Go is available; otherwise skip cleanly — the CLI
# and the Bash text menu work without it.
if command -v go >/dev/null 2>&1; then
	_rcc_step "Building the interactive TUI"
	if ( cd "${INSTALL_DIR}/ui" && go build -o "${INSTALL_DIR}/bin/rcc-ui" . ); then
		echo "✓ TUI built"
	else
		echo "⚠ TUI build failed — the text menu still works ('rcc' opens it)"
	fi
else
	echo "Go not found — skipping the optional TUI. The CLI and text menu work anyway;"
	echo "  for the richer TUI, install Go and re-run, or: brew install thousandflowers/tap/rcc"
fi

_rcc_done "Raccoon ${VERSION} is installed"
printf '\n'
printf "  Run %s'rcc help'%s to get started, or %s'rcc'%s for the menu.\n" \
	"$BOLD" "$NC" "$BOLD" "$NC"
