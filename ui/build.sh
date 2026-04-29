#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Go builds for the current platform by default:
#   arm64 on Apple Silicon, amd64 on Intel Macs
echo "Building rcc-ui..."
go build -o rcc-ui main.go
cp rcc-ui ../bin/rcc-ui
echo "✓ rcc-ui built and copied to bin/"
