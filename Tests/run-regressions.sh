#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for test_script in Tests/SourceRegressionTests/*.test.sh; do
  zsh "$test_script"
done

xcrun swiftc \
  PartyGames/Models/MahjongScoreModels.swift \
  PartyGames/Models/MahjongRealtimeProtocol.swift \
  Tests/ExecutableRegressionTests/MahjongRealtimeProtocolTest.swift \
  -o "$tmp_dir/realtime-protocol"
"$tmp_dir/realtime-protocol"

xcrun swiftc \
  PartyGames/Models/MahjongRoomActionState.swift \
  Tests/ExecutableRegressionTests/MahjongRoomActionStateTest.swift \
  -o "$tmp_dir/room-action-state"
"$tmp_dir/room-action-state"

xcrun swiftc \
  PartyGames/Models/MahjongSettlementValidation.swift \
  Tests/ExecutableRegressionTests/MahjongSettlementValidationTest.swift \
  -o "$tmp_dir/settlement-validation"
"$tmp_dir/settlement-validation"

xcrun swiftc \
  PartyGames/Services/NotificationPermissionStore.swift \
  Tests/ExecutableRegressionTests/NotificationPermissionDecisionTest.swift \
  -o "$tmp_dir/notification-permission"
"$tmp_dir/notification-permission"

xcrun swiftc \
  PartyGames/Models/MahjongRecentTablePolicy.swift \
  Tests/ExecutableRegressionTests/MahjongRecentTablePolicyTest.swift \
  -o "$tmp_dir/recent-table-policy"
"$tmp_dir/recent-table-policy"

xcrun swiftc \
  PartyGames/Services/MahjongMemberTokenStore.swift \
  Tests/ExecutableRegressionTests/MahjongMemberTokenStoreTest.swift \
  -o "$tmp_dir/member-token-store"
"$tmp_dir/member-token-store"

xcrun swiftc \
  PartyGames/Models/MahjongRoomToolbarPolicy.swift \
  Tests/ExecutableRegressionTests/MahjongRoomToolbarPolicyTest.swift \
  -o "$tmp_dir/room-toolbar-policy"
"$tmp_dir/room-toolbar-policy"

echo "All standalone regressions passed."
