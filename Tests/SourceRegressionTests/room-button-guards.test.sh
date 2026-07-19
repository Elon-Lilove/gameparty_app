#!/bin/zsh
set -euo pipefail

view="PartyGames/Views/components/MahjongScorekeeperView.swift"
view_model="PartyGames/ViewModels/MahjongScoreViewModel.swift"
web_main="web/mahjong-join/src/main.ts"
web_view="web/mahjong-join/src/room-view.ts"
web_styles="web/mahjong-join/src/styles.css"

rg -U -q 'Label\("踢出", systemImage: "person\.crop\.circle\.badge\.xmark"\)\n\s*}\n\s*\.disabled\(!viewModel\.canMutateRoom \|\| player\.score != 0\)' "$view"
rg -U -q 'Label\("退出", systemImage: "rectangle\.portrait\.and\.arrow\.right"\)\n\s*}\n\s*\.disabled\(!viewModel\.canMutateRoom \|\| player\.score != 0\)' "$view"
rg -q 'Text\("归零后可移除"\)' "$view"

if rg -U -q 'private func roomToolbar[\s\S]{0,500}ScrollView\(\.horizontal' "$view"; then
  echo "Room toolbar must not scroll horizontally" >&2
  exit 1
fi
rg -q 'MahjongRoomToolbarPolicy\.items\(isOwner: viewModel\.isOwner, isMultiplayer: snapshot\.room\.mode == \.multiplayer\)' "$view"
rg -q 'title: "玩家邀请"' "$view"
rg -q 'title: "房主转让"' "$view"
rg -q 'title: "语音播放"' "$view"
rg -q 'title: "台板（茶水）"' "$view"
if rg -q 'tableScoreButton\(|toolbarButton\("退出房间"' "$view"; then
  echo "Score and leave controls must not be rendered in the toolbar" >&2
  exit 1
fi
rg -q 'viewModel\.giveTableScore\(amount: amount\)' "$view"
rg -U -q 'private func transferMenu[\s\S]{0,900}\.disabled\(!viewModel\.canMutateRoom \|\| candidates\.isEmpty\)' "$view"
rg -U -q 'if viewModel\.tableServiceEnabled[\s\S]{0,120}snapshot\.room\.status == "active"[\s\S]{0,120}!hasTable' "$view"

if rg -U -q '\.room-tools \{[\s\S]{0,260}overflow-x: auto' "$web_styles"; then
  echo "Web room toolbar must not scroll horizontally" >&2
  exit 1
fi
rg -U -q '\.room-tools \{[\s\S]{0,180}display: flex' "$web_styles"
rg -U -q '\.room-tool \{[\s\S]{0,220}flex: 1 1 0' "$web_styles"
rg -U -q '\.room-tool \{[\s\S]{0,260}min-height: 44px' "$web_styles"
rg -q '\.tool-label' "$web_styles"
rg -U -q '@media \(max-width: 430px\)[\s\S]{0,500}grid-template-columns: minmax\(0, 1fr\) 58px 100px' "$web_styles"
rg -U -q '\.player-action \{[\s\S]{0,180}flex-wrap: wrap' "$web_styles"
rg -U -q '\.player-action button\.small \{[\s\S]{0,140}min-width: 44px' "$web_styles"
if rg -q '\[data-table-score\]' "$web_main"; then
  echo "Web must not bind removed fixed table-score buttons" >&2
  exit 1
fi
rg -q '\[data-table-give\]' "$web_main"
rg -U -q 'confirmTableScore[\s\S]{0,900}sendMutation\("table_score", \{ amount: result\.value \}\)' "$web_main"
rg -q 'kind: "table"' "$web_view"

if rg -q 'id="rejoin"|>重新加入<' "$web_main"; then
  echo "Removed memberships must not expose an impossible rejoin action" >&2
  exit 1
fi
rg -q '你已退出或被移出房间' "$web_main"
rg -q '请联系房主' "$web_main"
rg -U -q 'Task \{ await viewModel\.openRecentTable\(\) \}[\s\S]{0,1800}\.buttonStyle\(\.hapticPlain\)\n\s*\.disabled\(viewModel\.isLoading\)' "$view"
rg -U -q 'private func recentTableActionButton[\s\S]{0,900}\.buttonStyle\(\.hapticPlain\)\n\s*\.disabled\(viewModel\.isLoading\)' "$view"

if rg -U -q 'private func receiveRealtimeSnapshot[\s\S]{0,260}isRealtimeConnected = true' "$view_model"; then
  echo "Polling snapshots must not mark the WebSocket as connected" >&2
  exit 1
fi

rg -U -q 'var canMutateRoom: Bool \{\n\s+guard !isSettling,' "$view_model"
rg -U -q 'func settleRoom\(\) async \{\n\s+guard !isSettling,' "$view_model"
rg -q 'private var feedbackDismissTask: Task<Void, Never>?' "$view_model"
rg -U -q 'private func completeRealtimeAction[\s\S]{0,700}feedbackDismissTask\?\.cancel\(\)' "$view_model"

rg -U -q 'if snapshot\.room\.ownerDeviceId == viewModel\.currentDeviceId,\n\s+snapshot\.room\.status == "active"' "$view"
rg -U -q 'Button \{\n\s+if snapshot\.room\.status == "ended" \{\n\s+isRecentScoreDetailVisible = true\n\s+} else \{\n\s+Task \{ await viewModel\.openRecentTable\(\) \}' "$view"
