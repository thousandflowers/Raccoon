#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building rcc-ui..."
go build -o rcc-ui main.go
cp rcc-ui ../bin/rcc-ui
echo "✓ rcc-ui built and copied to bin/"
