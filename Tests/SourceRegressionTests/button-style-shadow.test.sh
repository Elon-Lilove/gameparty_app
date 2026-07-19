#!/bin/zsh
set -euo pipefail

style="PartyGames/Design/HapticPlainButtonStyle.swift"

if rg -q '\.glassEffect' "$style"; then
  echo "HapticPlainButtonStyle must not apply global glass effects" >&2
  exit 1
fi

rg -q 'scaleEffect\(configuration\.isPressed' "$style"
rg -q 'HapticService\.light\(\)' "$style"
