#!/bin/bash

set -e

REPO_URL="https://github.com/thousandflowers/Raccoon.git"
INSTALL_DIR="${HOME}/.raccoon"
BIN_DIR=""
VERSION="unknown"

if ! command -v git >/dev/null 2>&1; then
	echo "Error: git is required but not installed"
	echo "  Install with: brew install git   # or xcode-select --install"
	exit 1
fi

detect_bin_dir() {
	if [[ -w "/usr/local/bin" ]]; then
		echo "/usr/local/bin"
	elif [[ -w "/usr/local" ]]; then
		echo "/usr/local/bin"
	else
		echo "${HOME}/.local/bin"
	fi
}

get_version() {
	if [[ -f "${INSTALL_DIR}/lib/core/commands.sh" ]]; then
		grep '^VERSION=' "${INSTALL_DIR}/lib/core/commands.sh" | sed 's/VERSION="\([^"]*\)"/\1/'
	fi
}

echo "Installing Raccoon (rcc)..."

BIN_DIR=$(detect_bin_dir)
mkdir -p "${BIN_DIR}"

if [[ ! -d "${INSTALL_DIR}" ]]; then
	echo "Cloning repository..."
	git clone --depth 1 "$REPO_URL" "${INSTALL_DIR}"
else
	echo "Updating existing installation..."
	cd "${INSTALL_DIR}" && git pull -q
fi

VERSION=$(get_version)
[[ -z "$VERSION" || "$VERSION" == "unknown" ]] && VERSION="0.2.0"

# Make all bin scripts executable
chmod +x "${INSTALL_DIR}/bin/"*.sh 2>/dev/null || true

# Compile rcc-ui if Go is available
if command -v go &>/dev/null && [[ -f "${INSTALL_DIR}/ui/main.go" ]]; then
	echo "Compiling rcc-ui (Go UI)..."
	cd "${INSTALL_DIR}/ui" && go build -o ../bin/rcc-ui main.go 2>/dev/null || {
		echo "  Note: Go UI compilation failed, using bash menu fallback"
	}
else
	echo "  Note: Go not found, using bash menu fallback"
fi

if [[ ! -f "${BIN_DIR}/rcc" ]]; then
	ln -sf "${INSTALL_DIR}/rcc" "${BIN_DIR}/rcc"
	echo "Linked rcc to ${BIN_DIR}"
fi

chmod +x "${INSTALL_DIR}/rcc"
chmod +x "${BIN_DIR}/rcc" 2>/dev/null || true

echo ""
echo "✓ Raccoon installed successfully (v${VERSION})"
echo "  Run 'rcc help' to get started"
