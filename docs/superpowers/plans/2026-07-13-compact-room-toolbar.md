# Compact Room Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the iOS and scanned-web room toolbars with a compact, equal-width, single-row layout while preserving dynamic owner transfer and moving table scoring into the player-list flow.

**Architecture:** A small Swift policy defines role-driven toolbar items so owner changes immediately recompute the visible controls from the authoritative snapshot. iOS and Web render the same four labels and remove toolbar score/leave controls. Table scoring continues through the existing `table_score` mutation, opened from a synthetic or authoritative table row so a room with no table player can still start tea-service scoring.

**Tech Stack:** Swift 6, SwiftUI, TypeScript, Vite, Vitest, CSS, Cloudflare Durable Objects protocol already present in the repository.

## Global Constraints

- Apply to both the iOS room and scanned web room.
- The toolbar is one row with no horizontal scrolling or wrapping.
- Icons are left of the exact labels `玩家邀请`, `房主转让`, `语音播放`, and `台板（茶水）`.
- Visible buttons are equal width and at least 44pt/px high.
- Remove toolbar `+1`, `+5`, and `退出房间`; retain iOS player-row swipe exit and render Web exit in the current player's row.
- Current ownership always comes from the latest authoritative `ownerDeviceId`.
- Do not add dependencies or change the server mutation protocol.
- Because the working tree contains pre-existing overlapping untracked files, implementation checkpoints must not stage or commit those files without separate user authorization.

---

### Task 1: Role-Driven Swift Toolbar Policy

**Files:**
- Create: `PartyGames/Models/MahjongRoomToolbarPolicy.swift`
- Create: `Tests/ExecutableRegressionTests/MahjongRoomToolbarPolicyTest.swift`
- Modify: `Tests/run-regressions.sh`

**Interfaces:**
- Consumes: `isOwner: Bool` computed from the current authoritative room snapshot.
- Produces: `MahjongRoomToolbarItem` and `MahjongRoomToolbarPolicy.items(isOwner:) -> [MahjongRoomToolbarItem]`.

- [ ] **Step 1: Write the failing executable regression**

```swift
import Foundation

@main
struct MahjongRoomToolbarPolicyTest {
    static func main() {
        precondition(MahjongRoomToolbarPolicy.items(isOwner: true) == [.invite, .transferOwner, .voice, .table])
        precondition(MahjongRoomToolbarPolicy.items(isOwner: false) == [.invite, .voice, .table])
        precondition(MahjongRoomToolbarItem.invite.title == "玩家邀请")
        precondition(MahjongRoomToolbarItem.transferOwner.title == "房主转让")
        precondition(MahjongRoomToolbarItem.voice.title == "语音播放")
        precondition(MahjongRoomToolbarItem.table.title == "台板（茶水）")
    }
}
```

Add a `swiftc` invocation to `Tests/run-regressions.sh` using the new model and test files.

- [ ] **Step 2: Run the regression and verify RED**

Run: `zsh Tests/run-regressions.sh`

Expected: compilation fails because `MahjongRoomToolbarPolicy` and `MahjongRoomToolbarItem` do not exist.

- [ ] **Step 3: Implement the minimal policy**

```swift
enum MahjongRoomToolbarItem: CaseIterable, Equatable {
    case invite
    case transferOwner
    case voice
    case table

    var title: String {
        switch self {
        case .invite: "玩家邀请"
        case .transferOwner: "房主转让"
        case .voice: "语音播放"
        case .table: "台板（茶水）"
        }
    }
}

enum MahjongRoomToolbarPolicy {
    static func items(isOwner: Bool) -> [MahjongRoomToolbarItem] {
        isOwner ? [.invite, .transferOwner, .voice, .table] : [.invite, .voice, .table]
    }
}
```

- [ ] **Step 4: Run the regression and verify GREEN**

Run: `zsh Tests/run-regressions.sh`

Expected: `All standalone regressions passed.`

- [ ] **Step 5: Record a clean checkpoint**

Run: `git diff --check -- PartyGames/Models/MahjongRoomToolbarPolicy.swift Tests/ExecutableRegressionTests/MahjongRoomToolbarPolicyTest.swift Tests/run-regressions.sh`

Expected: exit 0. Do not stage these overlapping working-tree files.

### Task 2: Compact iOS Toolbar and Table-Row Scoring

**Files:**
- Modify: `Tests/SourceRegressionTests/room-button-guards.test.sh`
- Modify: `PartyGames/Views/components/MahjongScorekeeperView.swift`

**Interfaces:**
- Consumes: `MahjongRoomToolbarPolicy.items(isOwner:)`, `viewModel.currentDeviceId`, `viewModel.tableServiceEnabled`, and existing `giveTableScore(amount:)`.
- Produces: a non-scrolling equal-width `HStack`, a compact item label helper, and a table score dialog that reuses the existing amount field.

- [ ] **Step 1: Add failing source guards**

Require all of the following in `room-button-guards.test.sh`:

```zsh
if rg -U -q 'private func roomToolbar[\s\S]{0,300}ScrollView\(\.horizontal' "$view"; then
  echo "Room toolbar must not scroll horizontally" >&2
  exit 1
fi
rg -q 'MahjongRoomToolbarPolicy\.items\(isOwner: viewModel\.isOwner\)' "$view"
rg -q 'Text\("玩家邀请"\)' "$view"
rg -q 'Text\("房主转让"\)' "$view"
rg -q 'Text\("语音播放"\)' "$view"
rg -q 'Text\("台板（茶水）"\)' "$view"
if rg -q 'tableScoreButton\(|toolbarButton\("退出房间"' "$view"; then
  echo "Score and leave controls must not be rendered in the toolbar" >&2
  exit 1
fi
rg -q 'viewModel\.giveTableScore\(amount: amount\)' "$view"
```

- [ ] **Step 2: Run the source guard and verify RED**

Run: `zsh Tests/SourceRegressionTests/room-button-guards.test.sh`

Expected: failure because the toolbar still uses a horizontal `ScrollView` and renders score/leave controls.

- [ ] **Step 3: Implement the equal-width toolbar**

Replace the horizontal `ScrollView` with an `HStack(spacing: 4)` and render `MahjongRoomToolbarPolicy.items(isOwner:)`. Each item receives `.frame(maxWidth: .infinity, minHeight: 44)`. Use horizontal `Label` content with SF Symbols `person.badge.plus`, `person.crop.circle.badge.arrow.forward`, `speaker.wave.2.fill`, and `cup.and.saucer.fill`; apply `.lineLimit(1)` and `.minimumScaleFactor(0.65)`.

The transfer item must continue to use the existing `Menu`, whose candidates are recalculated from the current snapshot and exclude the current owner, table, and inactive players. Voice and table items use compact buttons that toggle their existing bindings and visually select the active state.

- [ ] **Step 4: Move table scoring to the table row**

When `tableServiceEnabled` is true and the snapshot has no table player, append a view-only player with id `__table_service__`, name `台板`, seat `table`, and score 0 to the displayed rows. The table row's `给分` button opens the existing amount dialog. On confirmation, detect the table seat and call:

```swift
if giveTargetPlayer?.seat == "table" || giveTargetPlayer?.name == "台板" {
    await viewModel.giveTableScore(amount: amount)
} else if let playerId = giveTargetPlayer?.id {
    await viewModel.giveScore(to: playerId, amount: amount)
}
```

This preserves the existing `table_score` mutation and creates the authoritative table player on first score.

- [ ] **Step 5: Run iOS guards and build**

Run: `zsh Tests/run-regressions.sh`

Expected: `All standalone regressions passed.`

Run: `xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Record a clean checkpoint**

Run: `git diff --check -- PartyGames/Views/components/MahjongScorekeeperView.swift Tests/SourceRegressionTests/room-button-guards.test.sh`

Expected: exit 0. Do not stage the pre-existing untracked Swift view.

### Task 3: Web Toolbar Rendering and Dynamic Ownership

**Files:**
- Modify: `web/mahjong-join/src/room-view.test.ts`
- Modify: `web/mahjong-join/src/room-view.ts`

**Interfaces:**
- Consumes: `isOwner(snapshot, deviceId)`, the current `RoomViewOptions`, and authoritative `snapshot.room.ownerDeviceId`.
- Produces: compact tool markup with `.tool-icon` and `.tool-label`, plus table-row score entry markup.

- [ ] **Step 1: Replace old expectations with failing compact-toolbar tests**

Add assertions that the owner HTML contains the labels in order, contains exactly four `room-tool` buttons, and contains neither `data-table-score` nor `data-action="leave"`. Add a second snapshot whose `ownerDeviceId` is `guest-device`; assert the guest render now contains `data-action="open-transfer"` while the old owner render does not. Assert that enabling table service adds a `data-table-give` row even when the snapshot has no table player, and disabling it removes that synthetic row. Add an authoritative table player and assert the same entry is used without rendering a duplicate.

```ts
const labels = ["玩家邀请", "房主转让", "语音播放", "台板（茶水）"];
let previousIndex = -1;
for (const label of labels) {
  const index = html.indexOf(label);
  expect(index).toBeGreaterThan(previousIndex);
  previousIndex = index;
}
expect(html.match(/class="room-tool/g)).toHaveLength(4);
expect(html).not.toContain("data-table-score");
expect(html).not.toContain('data-action="leave"');
```

- [ ] **Step 2: Run Vitest and verify RED**

Run: `npm test -- --run src/room-view.test.ts`

Working directory: `web/mahjong-join`

Expected: failures showing the old labels and toolbar score/leave controls.

- [ ] **Step 3: Implement compact role-driven markup**

Render `玩家邀请` for every active member, `房主转让` only when `owner === true`, and shared `语音播放` and `台板（茶水）` buttons. Each button uses:

```html
<button class="room-tool" data-action="...">
  <span class="tool-icon" aria-hidden="true">…</span>
  <span class="tool-label">文案</span>
</button>
```

Use the symbols `＋`, `⇄`, `▶`, and `♨` respectively. Remove `data-table-score` and toolbar leave markup. Render the guest's existing leave action in their own player row, preserving the zero-balance rule and disabled explanation. Build a `visiblePlayers` array before rendering: when `options.tableEnabled` is true and no active player has seat `table` or name `台板`, append a view-only player with id `__table_service__`, name `台板`, seat `table`, score 0, and the next sort order. For either the synthetic or authoritative table row, use `data-table-give` when `options.tableEnabled && canMutate`; otherwise render no table score action.

- [ ] **Step 4: Run the render tests and verify GREEN**

Run: `npm test -- --run src/room-view.test.ts`

Expected: all room-view tests pass.

- [ ] **Step 5: Record a clean checkpoint**

Run: `git diff --check -- web/mahjong-join/src/room-view.ts web/mahjong-join/src/room-view.test.ts`

Expected: exit 0. Do not stage the pre-existing untracked Web source.

### Task 4: Web Table Dialog and Non-Scrolling CSS

**Files:**
- Modify: `Tests/SourceRegressionTests/room-button-guards.test.sh`
- Modify: `web/mahjong-join/src/main.ts`
- Modify: `web/mahjong-join/src/room-view.ts`
- Modify: `web/mahjong-join/src/styles.css`

**Interfaces:**
- Consumes: `sendMutation("table_score", { amount })`, `RoomDialog`, and `data-table-give` from Task 3.
- Produces: `{ kind: "table"; value: string; error?: string }`, a table amount dialog, and an equal-width flex toolbar.

- [ ] **Step 1: Add failing source and render guards**

Require CSS to contain `overflow-x: visible`, `.room-tools { display: flex`, `.room-tool { flex: 1 1 0`, `.tool-label`, and a 44px minimum height. Reject `overflow-x: auto`. Require `main.ts` to bind `[data-table-give]` and send `table_score` from the confirmed table dialog; reject the old `[data-table-score]` listener.

- [ ] **Step 2: Run guards and verify RED**

Run: `zsh Tests/SourceRegressionTests/room-button-guards.test.sh`

Expected: failure because CSS still scrolls and `main.ts` still binds fixed score buttons.

- [ ] **Step 3: Implement the table dialog**

Extend `RoomDialog` with:

```ts
| { kind: "table"; value: string; error?: string }
```

Bind `[data-table-give]` to open `{ kind: "table", value: "1" }`. Render a numeric amount dialog with cancel and confirm actions. Parse with the existing `parseScoreAmount`; on success call `sendMutation("table_score", { amount: result.value })`, close the dialog, and retain existing pending/error feedback.

- [ ] **Step 4: Implement compact CSS**

Set `.room-tools` to a non-scrolling flex row with 4px gap and 6px horizontal padding. Set `.room-tool` to `flex: 1 1 0`, `min-width: 0`, `min-height: 44px`, 3px horizontal padding, inline-flex centering, and no wrapping. Set `.tool-icon` to 11px and `.tool-label` to `clamp(8px, 2.2vw, 11px)` with `white-space: nowrap` and `overflow: hidden`. Preserve selected and focus-visible states.

- [ ] **Step 5: Run Web tests and build**

Run: `npm test && npm run build && npm audit --omit=dev`

Working directory: `web/mahjong-join`

Expected: all tests pass, Vite production build succeeds, and audit reports 0 vulnerabilities.

- [ ] **Step 6: Record a clean checkpoint**

Run: `git diff --check -- web/mahjong-join/src/main.ts web/mahjong-join/src/room-view.ts web/mahjong-join/src/styles.css Tests/SourceRegressionTests/room-button-guards.test.sh`

Expected: exit 0. Do not stage overlapping untracked application files.

### Task 5: Cross-Platform Verification and Production Publication

**Files:**
- Modify: `docs/qa/mahjong-scorekeeper-interaction-matrix.md`

**Interfaces:**
- Consumes: completed iOS and Web implementations.
- Produces: updated QA evidence and production deployments.

- [ ] **Step 1: Update the QA matrix**

Record the single-row equal-width toolbar, exact four labels, removal of fixed table score/leave controls, table-row scoring, and repeated owner transfer behavior for both iOS and Web.

- [ ] **Step 2: Run the complete verification gate**

Run Worker: `npm test && npm run typecheck` in `cloudflare/mahjong-score-worker`.

Run Web: `npm test && npm run build && npm audit --omit=dev` in `web/mahjong-join`.

Run Swift: `zsh Tests/run-regressions.sh`.

Run iOS: `xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO`.

Run diff check: `git diff --check`.

Expected: Worker 18 tests pass, Web tests pass, audit reports 0 vulnerabilities, standalone regressions pass, iOS reports `BUILD SUCCEEDED`, and diff check exits 0.

- [ ] **Step 3: Review the final diff against the design**

Confirm no toolbar horizontal `ScrollView`/`overflow-x:auto`, no toolbar fixed score/leave buttons, exact labels and order, dynamic owner controls, table score entry, and no unrelated files modified by this task.

- [ ] **Step 4: Deploy the Web build**

Run: `npx netlify deploy --prod --dir=dist` in `web/mahjong-join`.

Expected: production URL `https://party-games-mahjong-join.netlify.app` reports deploy live. The Worker requires no deployment because its protocol is unchanged.

- [ ] **Step 5: Run production smoke checks**

Fetch the production HTML and hashed JavaScript asset; assert the asset contains `玩家邀请`, `房主转让`, `语音播放`, and `台板（茶水）`, and does not contain the old fixed table-score markup. Create a production room, join a guest, transfer ownership through WebSocket, and confirm the latest snapshot names the guest as owner and permits a transfer back.

- [ ] **Step 6: Preserve the dirty working tree**

Run: `git status --short`.

Expected: user pre-existing changes remain present. Do not stage, commit, reset, or discard overlapping implementation files.
