#!/bin/zsh
set -euo pipefail

service="PartyGames/Services/MahjongScoreService.swift"

if rg -q 'rooms/.*?/dismiss|/dismiss' "$service"; then
  echo "MahjongScoreService must not fall back to the unsupported dismiss endpoint" >&2
  exit 1
fi
