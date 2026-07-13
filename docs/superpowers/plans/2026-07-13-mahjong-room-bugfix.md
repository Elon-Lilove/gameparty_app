# Mahjong Room Bugfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair every Mahjong scorekeeper interaction, align the scanned-player web room with the iOS host room, and keep both clients synchronized through explicit real-time operation acknowledgements.

**Architecture:** The Cloudflare Durable Object remains the room coordinator and D1 remains the authoritative store. Every WebSocket mutation carries an `operationId`; the Worker returns it with the resulting `state` or `error` envelope so iOS and web can end pending UI states deterministically. SwiftUI and the TypeScript web app keep separate renderers but share the same permissions, validation, layout hierarchy, and service snapshot.

**Tech Stack:** Swift 6.2, SwiftUI/iOS 26, XCTest, TypeScript 5.7, Vite 5, Vitest, Cloudflare Workers, Durable Objects, D1, Wrangler 4.

## Global Constraints

- Preserve iOS 26 as the deployment target.
- Do not introduce another production room service.
- Multiplayer scores are service-authoritative and zero-sum.
- Score amounts must be integers in `1...1_000_000`; settlement multipliers must be in `(0, 1_000_000]`.
- Do not retry unacknowledged score mutations automatically.
- Preserve role permissions: only the owner can transfer ownership, remove another member, or settle.
- Do not stage, revert, or overwrite unrelated existing workspace changes.

---

### Task 1: Remove the accidental global option-button shadow

**Files:**
- Create: `Tests/SourceRegressionTests/button-style-shadow.test.sh`
- Modify: `PartyGames/Design/HapticPlainButtonStyle.swift`

**Interfaces:**
- Consumes: `.buttonStyle(.hapticPlain)` call sites throughout the app.
- Produces: a plain haptic press style with no implicit `glassEffect`; room-only glass remains in `RoomLiquidGlassControls.swift`.

- [ ] **Step 1: Write the failing source regression test**

```bash
#!/bin/zsh
set -euo pipefail
style="PartyGames/Design/HapticPlainButtonStyle.swift"
if rg -q '\.glassEffect' "$style"; then
  echo "HapticPlainButtonStyle must not apply global glass effects" >&2
  exit 1
fi
rg -q 'scaleEffect\(configuration\.isPressed' "$style"
rg -q 'HapticService\.light\(\)' "$style"
```

- [ ] **Step 2: Run the test and confirm it fails for the existing `glassEffect`**

Run: `zsh Tests/SourceRegressionTests/button-style-shadow.test.sh`

Expected: exit 1 with `must not apply global glass effects`.

- [ ] **Step 3: Remove only the implicit glass modifier**

```swift
configuration.label
    .scaleEffect(configuration.isPressed ? 0.96 : 1)
    .opacity(configuration.isPressed ? 0.92 : 1)
```

- [ ] **Step 4: Re-run the source regression test**

Run: `zsh Tests/SourceRegressionTests/button-style-shadow.test.sh`

Expected: exit 0.

### Task 2: Add operation acknowledgements to the room protocol

**Files:**
- Modify: `cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts`
- Modify: `cloudflare/mahjong-score-worker/test/worker-room.test.ts`
- Modify: `PartyGames/Services/MahjongRealtimeClient.swift`

**Interfaces:**
- Consumes: existing mutation messages such as `{ type: "give_score", targetPlayerId: "player-id", amount: 13 }`.
- Produces: messages with `operationId?: string`, plus server envelopes `{ type, snapshot?, error?, operationId?, actorDeviceId? }`.

- [ ] **Step 1: Extend the Worker test to require acknowledgement metadata**

```ts
const operationId = "give-13";
owner.socket.send(JSON.stringify({
  type: "give_score",
  targetPlayerId: guest?.id,
  amount: 13,
  operationId,
}));
const message = await owner.next();
expect(message.operationId).toBe(operationId);
expect(message.actorDeviceId).toBe("owner-device");
```

Also send an invalid score with `operationId: "invalid-score"` and require the returned error envelope to contain the same ID.

- [ ] **Step 2: Run the focused Worker test and confirm acknowledgement assertions fail**

Run: `npm test -- --run test/worker-room.test.ts`

Expected: failure because `operationId` and `actorDeviceId` are absent.

- [ ] **Step 3: Add optional protocol metadata and broadcast it after each mutation**

```ts
interface MutationMetadata {
  operationId?: string;
}

private mutationEnvelope(
  attachment: WebSocketAttachment,
  message: MutationMetadata,
  snapshot: RoomSnapshot,
) {
  return {
    type: "state",
    snapshot,
    operationId: message.operationId,
    actorDeviceId: attachment.deviceId,
  };
}
```

All mutation branches pass `operationId` into success broadcasts and error envelopes. Initial WebSocket snapshots omit acknowledgement metadata.

- [ ] **Step 4: Decode acknowledgement metadata in iOS**

```swift
struct MahjongRealtimeAcknowledgement: Equatable, Sendable {
    var operationId: String
    var actorDeviceId: String?
}

private struct MahjongRealtimeEnvelope: Decodable {
    var type: String
    var snapshot: MahjongRoomSnapshot?
    var error: String?
    var operationId: String?
    var actorDeviceId: String?
}
```

Change the snapshot and error callbacks to include an optional acknowledgement, and include `operationId` in every mutation encoder.

- [ ] **Step 5: Run Worker tests and type checking**

Run: `npm test`

Expected: 17 or more tests pass.

Run: `npm run typecheck`

Expected: exit 0.

### Task 3: Make iOS room actions pending, recoverable, and visible

**Files:**
- Create: `PartyGames/Models/MahjongRoomActionState.swift`
- Create: `Tests/PartyGamesUnitTests/MahjongRoomActionStateTests.swift`
- Modify: `PartyGames/ViewModels/MahjongScoreViewModel.swift`
- Modify: `PartyGames/Views/components/MahjongScorekeeperView.swift`

**Interfaces:**
- Consumes: `MahjongRealtimeAcknowledgement` from Task 2.
- Produces: `MahjongRoomPendingAction`, `begin(_:)`, `complete(operationId:)`, `fail(operationId:message:)`, and `canMutateRoom`.

- [ ] **Step 1: Write failing reducer tests**

```swift
func testMatchingAcknowledgementClearsPendingAction() {
    var state = MahjongRoomActionState()
    state.begin(.giveScore(targetPlayerId: "guest", operationId: "op-1"))
    state.complete(operationId: "op-1")
    XCTAssertNil(state.pending)
}

func testDifferentAcknowledgementDoesNotClearPendingAction() {
    var state = MahjongRoomActionState()
    state.begin(.giveScore(targetPlayerId: "guest", operationId: "op-1"))
    state.complete(operationId: "other")
    XCTAssertNotNil(state.pending)
}
```

- [ ] **Step 2: Run the focused iOS package test and confirm the new types are missing**

Run: `xcodebuild test -scheme PartyGames-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PartyGamesUnitTests/MahjongRoomActionStateTests`

Expected: build/test failure for missing `MahjongRoomActionState`.

- [ ] **Step 3: Implement the minimal action reducer**

```swift
enum MahjongRoomPendingAction: Equatable, Sendable {
    case giveScore(targetPlayerId: String, operationId: String)
    case tableScore(operationId: String)
    case rename(operationId: String)
    case removePlayer(operationId: String)
    case transferOwner(operationId: String)

    var operationId: String {
        switch self {
        case .giveScore(_, let operationId),
             .tableScore(let operationId),
             .rename(let operationId),
             .removePlayer(let operationId),
             .transferOwner(let operationId):
            return operationId
        }
    }
}

struct MahjongRoomActionState: Equatable, Sendable {
    private(set) var pending: MahjongRoomPendingAction?
    mutating func begin(_ action: MahjongRoomPendingAction) { guard pending == nil else { return }; pending = action }
    mutating func complete(operationId: String) { if pending?.operationId == operationId { pending = nil } }
    mutating func fail(operationId: String, message: String) { if pending?.operationId == operationId { pending = nil } }
}
```

- [ ] **Step 4: Route every iOS WebSocket mutation through the reducer**

Generate one UUID per click, begin the corresponding pending action before sending, clear it only on matching acknowledgement or error, and schedule a non-retrying 8-second timeout that restores the UI with `操作未确认，请重试`.

- [ ] **Step 5: Render room connection, error, and per-button progress states**

Add a compact room status row above the toolbar, expose the room error inside the navigation destination, disable all room mutations while one mutation is pending, and show `ProgressView` in the active give/table/transfer/remove action.

- [ ] **Step 6: Run reducer tests and an iOS simulator build**

Run: `xcodebuild test -scheme PartyGames-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PartyGamesUnitTests/MahjongRoomActionStateTests`

Expected: tests pass.

Run: `xcodebuild build -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .derivedData-local`

Expected: `BUILD SUCCEEDED`.

### Task 4: Give iOS settlement deterministic validation and feedback

**Files:**
- Create: `Tests/PartyGamesUnitTests/MahjongSettlementValidationTests.swift`
- Modify: `PartyGames/Models/MahjongRoomActionState.swift`
- Modify: `PartyGames/ViewModels/MahjongScoreViewModel.swift`
- Modify: `PartyGames/Views/components/MahjongScorekeeperView.swift`

**Interfaces:**
- Consumes: the existing `MahjongScoreService.settleRoom` `/settle` request.
- Produces: `MahjongSettlementValidation.parse(_:) -> Result<Double, MahjongSettlementValidationError>` and a visible settlement error.

- [ ] **Step 1: Write failing validation tests**

```swift
XCTAssertEqual(try MahjongSettlementValidation.parse("2").get(), 2)
XCTAssertThrowsError(try MahjongSettlementValidation.parse("0").get())
XCTAssertThrowsError(try MahjongSettlementValidation.parse("1000001").get())
XCTAssertThrowsError(try MahjongSettlementValidation.parse("abc").get())
```

- [ ] **Step 2: Run the focused test and confirm it fails because validation is missing**

Run: `xcodebuild test -scheme PartyGames-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PartyGamesUnitTests/MahjongSettlementValidationTests`

Expected: missing symbol failure.

- [ ] **Step 3: Implement strict multiplier parsing and use it before the HTTP request**

```swift
enum MahjongSettlementValidation {
    static func parse(_ raw: String) -> Result<Double, MahjongSettlementValidationError> {
        let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value, value > 0, value <= 1_000_000 else { return .failure(.outOfRange) }
        return .success(value)
    }
}
```

The ViewModel sets `isSettling` before the request, always clears it with `defer`, leaves the settlement alert open when validation fails, and displays HTTP errors inside the room.

- [ ] **Step 4: Run validation, service, and Worker settlement tests**

Run: `xcodebuild test -scheme PartyGames-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PartyGamesUnitTests/MahjongSettlementValidationTests -only-testing:PartyGamesUnitTests/MahjongScoreServiceTests`

Expected: all selected tests pass.

Run: `npm test -- --run test/worker-room.test.ts`

Expected: settlement test passes.

### Task 5: Replace web prompts with a testable room-action model

**Files:**
- Create: `web/mahjong-join/src/room-state.ts`
- Create: `web/mahjong-join/src/room-state.test.ts`
- Modify: `web/mahjong-join/package.json`
- Modify: `web/mahjong-join/src/main.ts`

**Interfaces:**
- Consumes: Worker envelopes from Task 2.
- Produces: `parseScoreAmount`, `canSendMutation`, `beginOperation`, `applyEnvelope`, `isOwner`, and `canGiveScore`.

- [ ] **Step 1: Add Vitest and write failing state tests**

```ts
it("accepts only integer score amounts in range", () => {
  expect(parseScoreAmount("13")).toEqual({ ok: true, value: 13 });
  expect(parseScoreAmount("0").ok).toBe(false);
  expect(parseScoreAmount("1.5").ok).toBe(false);
  expect(parseScoreAmount("1000001").ok).toBe(false);
});

it("clears only the matching pending operation", () => {
  const pending = beginOperation(undefined, "give_score", "op-1");
  expect(applyAcknowledgement(pending, { operationId: "other" })).toEqual(pending);
  expect(applyAcknowledgement(pending, { operationId: "op-1" })).toBeUndefined();
});
```

- [ ] **Step 2: Run the web tests and confirm the module is missing**

Run: `npm test`

Expected: failure because `room-state.ts` exports are missing.

- [ ] **Step 3: Implement the pure state helpers**

```ts
export function parseScoreAmount(raw: string): ParseResult {
  const value = Number(raw.trim());
  return Number.isInteger(value) && value >= 1 && value <= 1_000_000
    ? { ok: true, value }
    : { ok: false, message: "请输入 1 到 1000000 的整数" };
}

export function canSendMutation(state: RoomClientState): boolean {
  return state.connection === "connected" && state.snapshot?.room.status === "active" && !state.pending;
}
```

- [ ] **Step 4: Replace `prompt` and unguarded `send` calls**

Use an in-page modal for give score and settlement, assign `crypto.randomUUID()` as `operationId`, disable mutations until the matching acknowledgement, show success toasts, and clear pending with an error toast or an 8-second non-retrying timeout.

- [ ] **Step 5: Run web tests and type-aware production build**

Run: `npm test`

Expected: all web state tests pass.

Run: `npm run build`

Expected: Vite build exits 0.

### Task 6: Align the scanned-player web room with the iOS host room

**Files:**
- Modify: `web/mahjong-join/src/main.ts`
- Modify: `web/mahjong-join/src/styles.css`

**Interfaces:**
- Consumes: tested room state from Task 5.
- Produces: host-aligned header/status, tool strip, player table, details panel, bottom action bar, modal, and responsive states.

- [ ] **Step 1: Add static UI contract assertions to the web tests**

Render the active-room template and assert it contains `房间号`, `添加玩家` for owners, `转让群主` for owners, `语音播报`, `台板`, `给分详情`, and `结算房间`; render as a guest and assert owner-only controls are absent.

- [ ] **Step 2: Run tests and confirm the current simplified template fails the contract**

Run: `npm test`

Expected: missing host-aligned controls.

- [ ] **Step 3: Implement the shared information hierarchy**

The room template contains:

```html
<header class="room-header"><h1>房间号</h1><span class="connection-status">实时同步中</span></header>
<nav class="room-tools" aria-label="房间工具"><button>添加玩家</button><button>语音播报</button><button>台板</button></nav>
<section class="player-table" aria-label="玩家列表"><div class="player-row"></div></section>
<section class="score-details" aria-label="给分详情"><h2>给分详情</h2></section>
<footer class="room-bottom-bar"><button>给分详情</button><button>结算房间</button></footer>
<div class="modal-backdrop" role="presentation"><section role="dialog" aria-modal="true"></section></div>
```

Owner-only buttons are rendered from `isOwner(snapshot, deviceId)`. Guest controls keep the same positions but never expose unauthorized actions.

- [ ] **Step 4: Implement responsive host-aligned CSS without card shadows**

Use the existing cream/stone design tokens, red prominent actions, 8-point radii, 44px minimum hit targets, horizontally scrolling tools, sticky bottom controls, visible focus rings, and no `box-shadow` on option buttons or player rows.

- [ ] **Step 5: Run web tests and build**

Run: `npm test`

Run: `npm run build`

Expected: all tests pass and build exits 0.

### Task 7: Make the notification recommendation page respond exactly once

**Files:**
- Create: `Tests/PartyGamesUnitTests/NotificationPermissionDecisionTests.swift`
- Modify: `PartyGames/Services/NotificationPermissionStore.swift`
- Modify: `PartyGames/Views/components/NotificationPermissionView.swift`

**Interfaces:**
- Consumes: `UNAuthorizationStatus` and `UIApplication.openSettingsURLString`.
- Produces: `NotificationPermissionNextStep` and a request-in-progress/error/settings UI.

- [ ] **Step 1: Write failing permission-decision tests**

```swift
XCTAssertEqual(NotificationPermissionStore.nextStep(for: .notDetermined), .request)
XCTAssertEqual(NotificationPermissionStore.nextStep(for: .denied), .openSettings)
XCTAssertEqual(NotificationPermissionStore.nextStep(for: .authorized), .finish)
XCTAssertEqual(NotificationPermissionStore.nextStep(for: .provisional), .finish)
```

- [ ] **Step 2: Run the test and confirm `nextStep` is missing**

Run: `xcodebuild test -scheme PartyGames-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PartyGamesUnitTests/NotificationPermissionDecisionTests`

Expected: missing symbol failure.

- [ ] **Step 3: Implement the pure decision and guarded request flow**

```swift
enum NotificationPermissionNextStep: Equatable {
    case request
    case openSettings
    case finish
}

static func nextStep(for status: UNAuthorizationStatus) -> NotificationPermissionNextStep {
    switch status {
    case .notDetermined: .request
    case .denied: .openSettings
    case .authorized, .provisional, .ephemeral: .finish
    @unknown default: .openSettings
    }
}
```

The view uses `isRequesting` to reject repeat taps, a nonzero-opacity/content-shaped hot area aligned with the design image, a visible `ProgressView`, and an alert with a settings button for denied authorization.

- [ ] **Step 4: Run permission tests and simulator build**

Run: `xcodebuild test -scheme PartyGames-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PartyGamesUnitTests/NotificationPermissionDecisionTests`

Expected: tests pass.

Run: `xcodebuild build -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .derivedData-local`

Expected: `BUILD SUCCEEDED`.

### Task 8: Audit every Mahjong scorekeeper control and verify the complete room

**Files:**
- Create: `docs/qa/mahjong-scorekeeper-interaction-matrix.md`
- Modify only if a failing audit exposes a scoped defect in files already listed above.

**Interfaces:**
- Consumes: all completed tasks.
- Produces: a checked interaction matrix for start/resume/end/delete, invite/copy, transfer, voice/table toggles, table score, rename, give score, remove/leave, details, settlement, and modal cancel/confirm.

- [ ] **Step 1: Record every control and its expected visibility, enabled rule, immediate feedback, success result, and failure recovery**

Use one table row per control with the exact columns `Control`, `Role`, `Enabled when`, `Immediate feedback`, `Server/local result`, `Failure recovery`, and `Verification`.

- [ ] **Step 2: Run all automated verification**

Run: `zsh Tests/SourceRegressionTests/button-style-shadow.test.sh`

Run: `npm test` in `cloudflare/mahjong-score-worker`.

Run: `npm run typecheck` in `cloudflare/mahjong-score-worker`.

Run: `npm test` in `web/mahjong-join`.

Run: `npm run build` in `web/mahjong-join`.

Run: `xcodebuild test -scheme PartyGames-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .derivedData-local`

Run: `xcodebuild build -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .derivedData-local`

Expected: every command exits 0 with no test failures and `BUILD SUCCEEDED`.

- [ ] **Step 3: Run a local cross-client smoke test**

Start the Worker with `npm run dev -- --local --port 8787` and the web app with `VITE_MAHJONG_API_BASE_URL=http://localhost:8787 VITE_MAHJONG_WEBSOCKET_BASE_URL=http://localhost:8787 npm run dev -- --host 127.0.0.1`. Create a temporary room, join from a second browser context, and verify both clients receive identical snapshots after give score, table score, rename, ownership transfer, reconnect, and settlement.

- [ ] **Step 4: Inspect deployment identity before any production write**

Run: `npx wrangler whoami` and `npx wrangler deployments list` from the Worker directory; inspect Netlify linkage from `web/mahjong-join/.netlify/state.json` if present. If credentials or linkage are absent, report deployment as the remaining external step rather than guessing.

- [ ] **Step 5: Review the final diff and rerun the complete verification gate**

Run: `git diff --check`

Run: `git diff --stat`

Expected: no whitespace errors; only planned files and pre-existing user files are present.
