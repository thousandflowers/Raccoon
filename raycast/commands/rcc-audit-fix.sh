#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Raccoon Audit Fix
# @raycast.mode fullOutput
#
# Optional parameters:
# @raycast.icon 🦝
# @raycast.packageName Raccoon
#
# Documentation:
# @raycast.description audit --fix
# @raycast.author Eugenio Zamengo Pontrelli
# @raycast.authorURL https://github.com/thousandflowers/Raccoon

RCC="$(command -v rcc || echo "/opt/homebrew/bin/rcc")"
[[ -x "$RCC" ]] || { echo "rcc not found — brew install thousandflowers/tap/rcc"; exit 1; }

NO_COLOR=1 exec "${RCC}" audit fix
