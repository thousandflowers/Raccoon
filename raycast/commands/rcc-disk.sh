#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Raccoon Disk
# @raycast.mode fullOutput
#
# Optional parameters:
# @raycast.icon 🦝
# @raycast.packageName Raccoon
#
# Documentation:
# @raycast.description Disk space
# @raycast.author Eugenio Zamengo Pontrelli
# @raycast.authorURL https://github.com/thousandflowers/Raccoon

RCC="$(command -v rcc || echo "/opt/homebrew/bin/rcc")"
[[ -x "$RCC" ]] || { echo "rcc not found — brew install thousandflowers/raccoon/rcc"; exit 1; }

NO_COLOR=1 RCC_NO_PROMPT=1 exec "${RCC}" disk
