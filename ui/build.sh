#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building rcc-ui (universal: arm64 + amd64)..."

GOARCH=arm64 go build -o rcc-ui-arm64 main.go
GOARCH=amd64 go build -o rcc-ui-amd64 main.go
lipo -create -output rcc-ui rcc-ui-arm64 rcc-ui-amd64
rm -f rcc-ui-arm64 rcc-ui-amd64

cp rcc-ui ../bin/rcc-ui
echo "✓ rcc-ui universal binary built and copied to bin/"
