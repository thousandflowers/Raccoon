#!/bin/bash
# Menu dispatched from rcc entrypoint. Interactive_main_menu in commands.sh
# is the single source of truth. This file exists only as a symlink target
# for backward compatibility with old installs; do not add logic here.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/commands.sh"
interactive_main_menu