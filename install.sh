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

# True while the cursor sits on the top line of a drawn face, waiting to be
# redrawn over. _rcc_step sets it, _rcc_say clears it.
RCC_PARKED=false

# One frame of the raccoon, with a caption to its right.
# \033[K after each line: the frame is redrawn in place over the previous one,
# and without erasing to the end of the line a shorter caption left the tail of
# the longer one behind. "Linked rcc to /Users/x/.local/bin" followed by
# "Linked the man page" read as "Linked the man pageocal/bin".
_rcc_frame() {
	local eyes="$1" caption="$2"
	printf '   %sn___n%s\033[K\n' "$BOLD" "$NC"
	printf '  %s[ %s ]%s  %s\033[K\n' "$BOLD" "$eyes" "$NC" "$caption"
	printf '   %s> ^ <%s\033[K\n' "$BOLD" "$NC"
}

# Draw the face once, then redraw it in place while a step runs. Without a tty
# the caption is printed once and the cursor is left alone.
_rcc_step() {
	local caption="$1"
	if [[ "$ANIMATE" != "true" ]]; then
		printf '  %s\n' "$caption"
		return 0
	fi
	# A message since the last frame moved the cursor off the face, so start a
	# new one below it rather than redrawing three lines that are no longer
	# where the cursor thinks they are.
	[[ "$RCC_PARKED" == "true" ]] || printf '\n'
	local i
	for i in 0 1 2 3; do
		_rcc_frame "${RCC_EYES[$i]}" "$caption"
		sleep 0.08
		# Three lines up, to redraw over the face just printed.
		printf '\033[3A'
	done
	_rcc_frame "o.o" "$caption"
	printf '\033[3A'
	RCC_PARKED=true
}

# Between steps the cursor is parked on the top line of the face, so anything
# printed the ordinary way lands on the raccoon and shreds it. That is what
# broke the animation on a real install: git and go write to the terminal from
# inside the very step whose face is on screen. Messages go through here
# instead - it steps past the face and leaves the cursor below it.
_rcc_say() {
	if [[ "$ANIMATE" == "true" && "$RCC_PARKED" == "true" ]]; then
		printf '\033[3B'
	fi
	printf '%s\n' "$1"
	RCC_PARKED=false
}

# Leave the last frame on screen instead of scrolling past it.
_rcc_done() {
	if [[ "$ANIMATE" == "true" && "$RCC_PARKED" != "true" ]]; then
		printf '\n'
	fi
	_rcc_frame "^.^" "${GREEN}$1${NC}"
	RCC_PARKED=false
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
		# --quiet, and stderr away: the cursor is parked on the raccoon while
		# this runs, so git's progress lines land on its face.
		git checkout --quiet 2>/dev/null
	else
		git clone --quiet --depth 1 "$REPO_URL" "${INSTALL_DIR}" 2>/dev/null
	fi
}

if [[ ! -d "${INSTALL_DIR}" ]]; then
	_rcc_step "Cloning the repository"
	clone_repo
else
	_rcc_step "Updating your installation"
	# The hard reset prints "HEAD is now at ..." on stdout, straight onto the
	# parked face.
	cd "${INSTALL_DIR}" && git fetch --quiet --depth 1 origin main &&
		git reset --quiet --hard origin/main
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
	# go build writes to stderr, and stderr here is the terminal the face is
	# drawn on. Hold the output in a variable and show it only if the build
	# fails, where it is worth the reader's attention.
	if _rcc_build_out=$( ( cd "${INSTALL_DIR}/ui" && go build -o "${INSTALL_DIR}/bin/rcc-ui" . ) 2>&1 ); then
		_rcc_step "Built the interactive TUI"
	else
		_rcc_say "⚠ TUI build failed — the text menu still works ('rcc' opens it)"
		printf '%s\n' "$_rcc_build_out" | sed 's/^/    /' | head -10
	fi
else
	_rcc_say "Go not found — skipping the optional TUI. The CLI and text menu work anyway;"
	_rcc_say "  for the richer TUI, install Go and re-run, or: brew install thousandflowers/tap/rcc"
fi

_rcc_done "Raccoon ${VERSION} is installed"
printf '\n'
printf "  Run %s'rcc help'%s to get started, or %s'rcc'%s for the menu.\n" \
	"$BOLD" "$NC" "$BOLD" "$NC"
