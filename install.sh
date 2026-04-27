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

if [[ ! -f "${BIN_DIR}/rcc" ]]; then
	ln -sf "${INSTALL_DIR}/rcc" "${BIN_DIR}/rcc"
	echo "Linked rcc to ${BIN_DIR}"
fi

chmod +x "${INSTALL_DIR}/rcc"
chmod +x "${BIN_DIR}/rcc" 2>/dev/null || true

echo ""
echo "✓ Raccoon installed successfully (v${VERSION})"
echo "  Run 'rcc help' to get started"
