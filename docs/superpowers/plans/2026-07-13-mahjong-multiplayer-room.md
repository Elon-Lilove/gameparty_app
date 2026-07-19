# 麻将计分多人房间改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复线上多人房间协议与结算，完成扫码加入、零和给分、台板、转让群主、断线恢复及 iOS 26 Liquid Glass 房间交互。

**Architecture:** Cloudflare Durable Object 串行处理每个房间的命令，D1 原子 batch 持久化房间、成员、玩家和流水，并在每次成功变更后广播完整快照。iOS 只发送用户意图，以服务端快照为准；邀请通过 HTTPS 网页链接加入，WebSocket 负责实时同步。

**Tech Stack:** Swift 6.3、SwiftUI on iOS 26、Observation、AVSpeechSynthesizer、Swift Testing、Cloudflare Workers、Durable Objects、D1、TypeScript、Vitest、Vite、Netlify、Wrangler。

## Global Constraints

- 部署目标保持 iOS 26.0，不添加第三方 iOS UI 依赖。
- 多人建房初始只创建房主本人；其他真实玩家只能扫码或打开网页链接加入。
- 二维码和可复制链接必须编码同一个 HTTPS URL；邀请使用底部 sheet，不使用独立导航页。
- 多人计分只能通过零和转账；给分整数范围为 `1...1_000_000`。
- 结算倍率范围为 `(0, 1_000_000]`，只有当前房主可结算。
- 普通断网不得显示“你已退出房间”；只有服务端快照确认本人已不在成员列表时显示该文案。
- 房间模块所有按钮使用 iOS 26 原生 Liquid Glass 按压反馈，并通过现有 `HapticService` 提供触觉反馈。
- 保留应用现有视觉语言，不引入参考小程序的紫色主题、广告或品牌元素。
- 不回滚工作区中已有的用户修改；每次提交只暂存本任务明确列出的文件。

---

## File Structure

### Worker

- `cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts`：房间 HTTP/WS 命令、权限、D1 原子更新和广播。
- `cloudflare/mahjong-score-worker/src/index.ts`：公开 HTTP 路由，新增 `/settle` 并转发认证头和请求体。
- `cloudflare/mahjong-score-worker/src/types.ts`：房间、玩家、成员、事件和消息共享类型。
- `cloudflare/mahjong-score-worker/vitest.config.ts`：Cloudflare Workers Vitest pool 配置。
- `cloudflare/mahjong-score-worker/test/setup.ts`：测试 D1 schema 初始化。
- `cloudflare/mahjong-score-worker/test/sql.d.ts`：允许 Vitest 以 raw string 导入 D1 migrations。
- `cloudflare/mahjong-score-worker/test/worker-room.test.ts`：生产 Worker 的创建、加入、WS 命令、权限和结算集成测试。

### Web Join

- `web/mahjong-join/src/main.ts`：已结束房间、网络断开和成员退出的独立文案与状态。

### iOS Domain And Services

- `Package.swift`：增加 iOS 单元测试 target。
- `PartyGames/Models/MahjongScoreModels.swift`：连接状态、给分校验和事件辅助模型。
- `PartyGames/Services/MahjongRoomCommand.swift`：可测试的 WebSocket 命令编码模型。
- `PartyGames/Services/MahjongRoomDependencies.swift`：Service/Realtime 协议，供 ViewModel 注入测试替身。
- `PartyGames/Services/MahjongRealtimeClient.swift`：命令发送、心跳、重连和结构化错误。
- `PartyGames/Services/MahjongScoreService.swift`：直接调用 `/settle`、HTTPS 邀请 URL 和可注入 URLSession。
- `PartyGames/Services/MahjongVoiceAnnouncer.swift`：只播报新计分事件并去重。
- `Tests/PartyGamesUnitTests/URLProtocolStub.swift`：URLSession 请求捕获桩。
- `Tests/PartyGamesUnitTests/MahjongScoreServiceTests.swift`：HTTP 路径、body、token、邀请 URL 和错误映射测试。
- `Tests/PartyGamesUnitTests/MahjongRoomCommandTests.swift`：WS 命令 JSON 测试。
- `Tests/PartyGamesUnitTests/MahjongRoomTestDoubles.swift`：ViewModel 的 Service/Realtime 测试替身。
- `Tests/PartyGamesUnitTests/MahjongScoreViewModelTests.swift`：房间状态、权限、重连、退出和语音去重测试。

### iOS UI

- `PartyGames/Design/RoomLiquidGlassControls.swift`：房间按钮、开关、prominent 层级和触觉反馈的统一封装。
- `PartyGames/Views/components/MahjongRoomToolbar.swift`：添加玩家、转让群主、台板和语音播报。
- `PartyGames/Views/components/MahjongInviteSheet.swift`：二维码、网页链接复制和底部 sheet 内容。
- `PartyGames/Views/components/MahjongGiveScoreDialog.swift`：紧凑给分弹框、输入校验和双方预览。
- `PartyGames/Views/components/MahjongScorekeeperView.swift`：房间页面编排、玩家列表、明细和结算入口。
- `PartyGames/ViewModels/MahjongScoreViewModel.swift`：权威快照、进行中操作、连接状态和 UI 派生状态。

---

### Task 1: Worker 测试基建与多人创建/加入规则

**Files:**
- Modify: `cloudflare/mahjong-score-worker/package.json`
- Modify: `cloudflare/mahjong-score-worker/package-lock.json`
- Create: `cloudflare/mahjong-score-worker/vitest.config.ts`
- Create: `cloudflare/mahjong-score-worker/test/setup.ts`
- Create: `cloudflare/mahjong-score-worker/test/sql.d.ts`
- Create: `cloudflare/mahjong-score-worker/test/worker-room.test.ts`
- Modify: `cloudflare/mahjong-score-worker/src/index.ts:5-20`
- Modify: `cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts:6-220`

**Interfaces:**
- Consumes: D1 migrations `0001_init.sql` and `0002_room_player_fields.sql`.
- Produces: `POST /rooms` 的多人单房主语义、`POST /rooms/:code/join` 的幂等扫码加入语义、可复用测试 helper `createRoom()` 和 `joinRoom()`。

- [ ] **Step 1: 安装 Cloudflare Vitest pool**

Run:

```bash
cd cloudflare/mahjong-score-worker
npm install --save-dev @cloudflare/vitest-pool-workers
```

Expected: `package.json` 和 lockfile 新增 `@cloudflare/vitest-pool-workers`，命令退出码为 0。

- [ ] **Step 2: 配置真实 Worker/D1 测试环境**

Create `vitest.config.ts`:

```ts
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    setupFiles: ["./test/setup.ts"],
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
      },
    },
  },
});
```

Create `test/setup.ts`:

```ts
import { env } from "cloudflare:test";
import { beforeAll } from "vitest";
import initSQL from "../migrations/0001_init.sql?raw";
import roomFieldsSQL from "../migrations/0002_room_player_fields.sql?raw";

beforeAll(async () => {
  await env.DB.exec(initSQL);
  await env.DB.exec(roomFieldsSQL);
});
```

Create `test/sql.d.ts`:

```ts
declare module "*.sql?raw" {
  const sql: string;
  export default sql;
}
```

- [ ] **Step 3: 写创建与加入的失败测试**

Create `test/worker-room.test.ts` with helpers and assertions:

```ts
import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

async function createRoom(overrides: Record<string, unknown> = {}) {
  const response = await SELF.fetch("https://worker.test/rooms", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      deviceId: "owner-device",
      displayName: "阿龙",
      title: "麻将计分",
      mode: "multiplayer",
      startingScore: 0,
      players: [{ name: "错误的预置玩家" }, { name: "不应出现" }],
      ...overrides,
    }),
  });
  expect(response.status).toBe(200);
  return response.json() as Promise<any>;
}

async function joinRoom(code: string, deviceId: string, displayName: string) {
  const response = await SELF.fetch(`https://worker.test/rooms/${code}/join`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ deviceId, displayName }),
  });
  return { response, body: await response.json() as any };
}

describe("multiplayer room lifecycle", () => {
  it("creates only the bound owner player", async () => {
    const created = await createRoom();
    expect(created.snapshot.players).toEqual([
      expect.objectContaining({ name: "阿龙", deviceId: "owner-device", score: 0 }),
    ]);
  });

  it("joins once per device and uses the submitted display name", async () => {
    const created = await createRoom();
    const first = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const second = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    expect(first.response.status).toBe(200);
    expect(second.body.snapshot.players.filter((p: any) => p.deviceId === "guest-device")).toHaveLength(1);
    expect(second.body.snapshot.players).toContainEqual(expect.objectContaining({ name: "小雨" }));
  });
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `cd cloudflare/mahjong-score-worker && npm test -- worker-room.test.ts`

Expected: FAIL because multiplayer creation still honors the submitted `players` array and joined players are named by seat index.

- [ ] **Step 5: 最小实现多人创建与幂等加入**

Update both `CreateRoomRequest` in `index.ts` and `CreateRoomBody` in `MahjongRoomObject.ts` to include `mode?: "multiplayer" | "solo"`. In `handleCreate`, normalize `mode`, create exactly one owner player for multiplayer, insert `mode`, and use `displayName`:

```ts
const mode = this.normalizeMode(body.mode);
const players = mode === "multiplayer"
  ? [this.normalizeOwnerPlayer(roomId, ownerDeviceId, displayName, startingScore)]
  : this.normalizePlayers(body.players, startingScore, roomId, ownerDeviceId);

`INSERT INTO mahjong_rooms (id, code, title, status, mode, starting_score, owner_device_id)
 VALUES (?, ?, ?, 'active', ?, ?, ?)`
```

Add helpers:

```ts
private normalizeOwnerPlayer(roomId: string, deviceId: string, displayName: string, score: number): PlayerRow {
  return {
    id: crypto.randomUUID(), room_id: roomId, name: displayName,
    device_id: deviceId, seat: null, score, multiplier_score: score,
    result: null, sort_order: 0, is_active: 1,
    created_at: "", updated_at: "",
  };
}

private normalizeMode(value: unknown): "multiplayer" | "solo" {
  if (value === undefined) return "multiplayer";
  if (value !== "multiplayer" && value !== "solo") throw new HttpError(400, "mode must be multiplayer or solo");
  return value;
}
```

Change `normalizeJoinedPlayer` so `name: displayName`, reject `room.status !== "active"` before creating a member, and keep the existing active-player lookup to make repeated joins idempotent.

- [ ] **Step 6: 运行 Worker 测试和类型检查**

Run:

```bash
cd cloudflare/mahjong-score-worker
npm test
npm run typecheck
```

Expected: all Vitest tests PASS and TypeScript exits 0.

- [ ] **Step 7: 提交创建/加入规则**

```bash
git add cloudflare/mahjong-score-worker/package.json cloudflare/mahjong-score-worker/package-lock.json cloudflare/mahjong-score-worker/vitest.config.ts cloudflare/mahjong-score-worker/test/setup.ts cloudflare/mahjong-score-worker/test/sql.d.ts cloudflare/mahjong-score-worker/test/worker-room.test.ts cloudflare/mahjong-score-worker/src/index.ts cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts
git commit -m "fix: enforce multiplayer room membership"
```

---

### Task 2: Durable Object 多人 WebSocket 命令与权限

**Files:**
- Modify: `cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts:20-390`
- Modify: `cloudflare/mahjong-score-worker/src/types.ts:1-110`
- Modify: `cloudflare/mahjong-score-worker/test/worker-room.test.ts`

**Interfaces:**
- Consumes: Task 1 的真实 Worker 测试 helper 和绑定设备玩家。
- Produces: `give_score`、`table_score`、`rename_player`、`add_player`、`remove_player`、`transfer_owner`、`adjust_score` 的生产实现。

- [ ] **Step 1: 写 WebSocket 行为失败测试**

Add a WebSocket helper to `worker-room.test.ts`:

```ts
async function connectRoom(code: string, memberToken: string) {
  const response = await SELF.fetch(`https://worker.test/rooms/${code}/ws?memberToken=${encodeURIComponent(memberToken)}`, {
    headers: { upgrade: "websocket" },
  });
  const socket = response.webSocket!;
  socket.accept();
  const next = () => new Promise<any>((resolve) => socket.addEventListener("message", (event) => resolve(JSON.parse(String(event.data))), { once: true }));
  await next();
  return { socket, next };
}
```

Add tests that assert:

```ts
owner.socket.send(JSON.stringify({ type: "give_score", targetPlayerId: guestId, amount: 13 }));
const transfer = await owner.next();
expect(transfer.snapshot.players.find((p: any) => p.deviceId === "owner-device").score).toBe(-13);
expect(transfer.snapshot.players.find((p: any) => p.id === guestId).score).toBe(13);
expect(transfer.snapshot.recentEvents.filter((e: any) => Math.abs(e.delta) === 13)).toHaveLength(2);

owner.socket.send(JSON.stringify({ type: "table_score", amount: 7 }));
const table = await owner.next();
expect(table.snapshot.players).toContainEqual(expect.objectContaining({ name: "台板", seat: "table", score: 7 }));

guest.socket.send(JSON.stringify({ type: "transfer_owner", targetDeviceId: "owner-device" }));
expect((await guest.next()).error).toMatch(/Only the room owner/);
```

Also cover self-give rejection, amount `0` and `1_000_001`, multiplayer `adjust_score` rejection, owner transfer to a real member, owner kick, member self-exit, rename-own-player, and a kicked member failing to reconnect with its old token.

- [ ] **Step 2: 运行测试确认协议缺失**

Run: `cd cloudflare/mahjong-score-worker && npm test -- worker-room.test.ts`

Expected: FAIL with `Unsupported message type` for the new commands.

- [ ] **Step 3: 扩展命令联合类型和分发器**

Define exact command shapes:

```ts
type ClientMessage =
  | { type: "adjust_score"; playerId: string; delta: number; reason?: string }
  | { type: "give_score"; targetPlayerId: string; amount: number; reason?: string }
  | { type: "rename_player"; playerId: string; name: string }
  | { type: "add_player"; name: string }
  | { type: "remove_player"; playerId: string }
  | { type: "table_score"; amount: number }
  | { type: "transfer_owner"; targetDeviceId: string }
  | { type: "ping" };
```

Dispatch every command to a named async method, then call a single helper after successful mutations:

```ts
private async broadcastRoom(roomId: string): Promise<void> {
  this.broadcast({ type: "state", snapshot: await this.getSnapshotByRoomId(roomId) });
}
```

- [ ] **Step 4: 实现零和给分与台板原子 batch**

For `giveScore`, load active room, acting player by `attachment.deviceId`, and active target by `targetPlayerId`; reject self-target and invalid amount. Execute one D1 batch containing source decrement, source event, target increment, target event, and room timestamp update. For `tableScore`, create the `seat = 'table'` row if absent, then execute the same two-sided batch with reason `台板(茶水)`.

Use these shared validators:

```ts
private normalizeScoreAmount(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0 || value > 1_000_000) {
    throw new HttpError(400, "amount must be an integer between 1 and 1000000");
  }
  return value;
}

private requireActiveRoom(room: RoomRow | null): RoomRow {
  if (!room) throw new HttpError(404, "Room not found");
  if (room.status !== "active") throw new HttpError(409, "Room is not active");
  return room;
}
```

- [ ] **Step 5: 实现改名、单人加人、退出/踢出和转让群主**

Apply these exact permissions:

```text
rename_player: 本人可改自己的绑定玩家；solo 房主可改未绑定玩家。
add_player: 仅 solo 房主，最多 20 人；multiplayer 返回 403。
remove_player: 房主可移除其他真实成员；普通成员只能移除自己；房主不能移除自己。
transfer_owner: 仅当前房主；目标 deviceId 必须有活跃 member 和活跃绑定玩家。
adjust_score: 仅 solo 房主；multiplayer 返回 400 "Use give_score in multiplayer rooms"。
```

When removing a real player, set `is_active = 0`, delete the matching member, update the room timestamp, and broadcast. When transferring, update `mahjong_rooms.owner_device_id` and atomically change old/new member roles.

In `handleWebSocket`, verify that the token still maps to an existing member before accepting the socket:

```ts
const member = await this.env.DB.prepare(
  "SELECT id FROM mahjong_room_members WHERE id = ? AND room_id = ? AND device_id = ?",
).bind(payload.memberId, payload.roomId, payload.deviceId).first<{ id: string }>();
if (!member) throw new HttpError(403, "Room membership is no longer active");
```

- [ ] **Step 6: 运行完整 Worker 验证**

Run:

```bash
cd cloudflare/mahjong-score-worker
npm test
npm run typecheck
```

Expected: protocol, permission, existing room-code and limit tests all PASS.

- [ ] **Step 7: 提交 WebSocket 协议**

```bash
git add cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts cloudflare/mahjong-score-worker/src/types.ts cloudflare/mahjong-score-worker/test/worker-room.test.ts
git commit -m "feat: add multiplayer room commands"
```

---

### Task 3: 权威结算路由与结束权限

**Files:**
- Modify: `cloudflare/mahjong-score-worker/src/index.ts:1-150`
- Modify: `cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts:55-280`
- Modify: `cloudflare/mahjong-score-worker/test/worker-room.test.ts`

**Interfaces:**
- Consumes: Bearer member token、Task 2 的权限和广播 helper。
- Produces: `POST /rooms/:code/settle`，返回 `{ snapshot }`；兼容 `/end` 但收紧为房主权限。

- [ ] **Step 1: 写结算失败测试**

Add tests:

```ts
const response = await SELF.fetch(`https://worker.test/rooms/${code}/settle`, {
  method: "POST",
  headers: { authorization: `Bearer ${ownerToken}`, "content-type": "application/json" },
  body: JSON.stringify({ multiplier: 2 }),
});
const body = await response.json() as any;
expect(response.status).toBe(200);
expect(body.snapshot.room).toEqual(expect.objectContaining({ status: "ended", multiplier: 2 }));
expect(body.snapshot.players.find((p: any) => p.score === 13)).toEqual(expect.objectContaining({ result: "win", multiplierScore: 26 }));
expect(body.snapshot.players.find((p: any) => p.score === -13)).toEqual(expect.objectContaining({ result: "lose", multiplierScore: -26 }));
```

Add non-owner `403`, multiplier `0`/`1_000_001` rejection, writes-after-settlement rejection, and `/end` non-owner `403` assertions.

- [ ] **Step 2: 运行测试确认 `/settle` 不存在**

Run: `cd cloudflare/mahjong-score-worker && npm test -- worker-room.test.ts`

Expected: FAIL with status 404 for `/settle`.

- [ ] **Step 3: 添加公开和 Durable Object 路由**

In `index.ts`:

```ts
if (request.method === "POST" && pathParts[2] === "settle") {
  return forwardToRoom(env, code, "/settle", await readJson<{ multiplier?: number }>(request), "POST", request.headers);
}
```

In `MahjongRoomObject.fetch`, route `/settle` to `handleSettle`.

- [ ] **Step 4: 实现房主结算 batch**

Validate token room and `payload.deviceId === room.owner_device_id`. Normalize multiplier with `(0, 1_000_000]`. Read all active players, calculate:

```ts
const result = player.score > 0 ? "win" : player.score < 0 ? "lose" : "draw";
const multiplierScore = player.score * multiplier;
```

Use one D1 batch to update every player plus room `status = 'ended'`, `multiplier`, `ended_at`, and `updated_at`; broadcast and return `{ snapshot }`. Add the same owner check to legacy `handleEnd`.

- [ ] **Step 5: 运行测试与类型检查**

Run:

```bash
cd cloudflare/mahjong-score-worker
npm test
npm run typecheck
```

Expected: all tests PASS; ended rooms reject join and every WS mutation.

- [ ] **Step 6: 提交结算实现**

```bash
git add cloudflare/mahjong-score-worker/src/index.ts cloudflare/mahjong-score-worker/src/MahjongRoomObject.ts cloudflare/mahjong-score-worker/test/worker-room.test.ts
git commit -m "fix: settle rooms with owner authority"
```

---

### Task 4: 网页加入页区分结束、退出和网络错误

**Files:**
- Modify: `web/mahjong-join/src/main.ts:60-125,190-215`

**Interfaces:**
- Consumes: Worker 的 HTTP status 和 `{ error }` body。
- Produces: 首次打开已结束二维码时显示“房间已结束”，网络错误显示重试，不误显示“你已退出房间”。

- [ ] **Step 1: 记录当前失败行为**

Run: `cd web/mahjong-join && npm run build`

Expected: build PASS, but inspection confirms initialization catch only exposes a generic error and `hasLeft` rendering always says “你已退出房间”。

- [ ] **Step 2: 增加结构化网页错误**

Add:

```ts
class RoomRequestError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

async function readRoomError(response: Response): Promise<never> {
  const body = await response.json().catch(() => ({ error: "请求失败" })) as { error?: string };
  throw new RoomRequestError(response.status, body.error ?? "请求失败");
}
```

Map status/message in initialization:

```ts
if (error instanceof RoomRequestError && /not active|ended/i.test(error.message)) {
  renderTerminalState("房间已结束", "本局已经结算，无法再加入。");
} else {
  renderRetryState("网络连接似乎出现问题", "请检查网络后重试。");
}
```

Keep `state.hasLeft` exclusively for an explicit leave action or a snapshot where the current bound player disappeared.

- [ ] **Step 3: 构建网页加入页**

Run: `cd web/mahjong-join && npm run build`

Expected: `tsc`/Vite build exits 0 and generates `dist/index.html` plus assets.

- [ ] **Step 4: 提交网页状态修复**

```bash
git add web/mahjong-join/src/main.ts
git commit -m "fix: clarify mahjong join states"
```

---

### Task 5: iOS HTTP/WS 协议测试与 `/settle` 修复

**Files:**
- Modify: `Package.swift`
- Create: `PartyGames/Services/MahjongRoomCommand.swift`
- Create: `PartyGames/Services/MahjongRoomDependencies.swift`
- Modify: `PartyGames/Services/MahjongRealtimeClient.swift:1-230`
- Modify: `PartyGames/Services/MahjongScoreService.swift:1-180`
- Create: `Tests/PartyGamesUnitTests/URLProtocolStub.swift`
- Create: `Tests/PartyGamesUnitTests/MahjongScoreServiceTests.swift`
- Create: `Tests/PartyGamesUnitTests/MahjongRoomCommandTests.swift`
- Create: `Tests/PartyGamesUnitTests/MahjongRoomTestDoubles.swift`

**Interfaces:**
- Consumes: Worker commands and `/settle` contract from Tasks 2-3。
- Produces: `MahjongRoomCommand`、`MahjongScoreServicing`、`MahjongRealtimeConnecting`、可注入的 `MahjongScoreService`、直接结算请求和可测试 JSON。

- [ ] **Step 1: 增加 SwiftPM 测试 target**

Update `Package.swift`:

```swift
.testTarget(
    name: "PartyGamesUnitTests",
    dependencies: ["PartyGames"],
    path: "Tests/PartyGamesUnitTests"
),
```

- [ ] **Step 2: 写 Service 与命令失败测试**

Create a `URLProtocolStub` that captures the request and returns configured JSON. Assert:

```swift
@Test func settleUsesAuthoritativeEndpoint() async throws {
    let service = MahjongScoreService(baseURL: URL(string: "https://example.test/api")!, session: stubSession)
    _ = try await service.settleRoom(code: "ab12cd", memberToken: "member-token", multiplier: 2)
    #expect(URLProtocolStub.lastRequest?.url?.path == "/api/rooms/AB12CD/settle")
    #expect(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "authorization") == "Bearer member-token")
    #expect(String(data: URLProtocolStub.lastRequest!.httpBody!, encoding: .utf8)!.contains("\"multiplier\":2"))
}

@Test func inviteURLIsHTTPSAndContainsRoom() throws {
    let url = try MahjongScoreService().inviteURL(roomCode: "ab12cd")
    #expect(url.scheme == "https")
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "room", value: "AB12CD")) == true)
}
```

Create command encoding tests for all seven mutating WS commands and `ping`.

- [ ] **Step 3: 运行测试确认 `/end` 失败**

Run:

```bash
xcodebuild -scheme PartyGames-Package -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local test
```

Expected: FAIL because `settleRoom` requests `/end` first and the command model does not exist.

- [ ] **Step 4: 提取命令模型并修复 Service**

Create:

```swift
enum MahjongRoomCommand: Encodable, Equatable, Sendable {
    case adjustScore(playerId: String, delta: Int)
    case giveScore(targetPlayerId: String, amount: Int)
    case renamePlayer(playerId: String, name: String)
    case addPlayer(name: String)
    case removePlayer(playerId: String)
    case tableScore(amount: Int)
    case transferOwner(targetDeviceId: String)
    case ping
}
```

Create `MahjongRoomDependencies.swift` with these exact contracts:

```swift
protocol MahjongScoreServicing: Sendable {
    func createRoom(_ request: MahjongCreateRoomRequest) async throws -> MahjongRoomResponse
    func joinRoom(code: String, request: MahjongJoinRoomRequest) async throws -> MahjongRoomResponse
    func loadUnfinishedRooms(deviceId: String) async throws -> MahjongRoomHistoryResponse
    func loadRoom(code: String) async throws -> MahjongRoomSnapshot
    func settleRoom(code: String, memberToken: String, multiplier: Double) async throws -> MahjongSettleRoomResponse
    func dismissRoom(code: String, memberToken: String) async throws
    func inviteURL(roomCode: String) throws -> URL
    func webSocketURL(roomCode: String, memberToken: String) throws -> URL
}

@MainActor
protocol MahjongRealtimeConnecting: AnyObject {
    func connect(
        url: URL,
        onSnapshot: @escaping @Sendable (MahjongRoomSnapshot) -> Void,
        onStatus: @escaping @Sendable (MahjongRealtimeConnectionState) -> Void,
        onError: @escaping @Sendable (String) -> Void
    )
    func send(_ command: MahjongRoomCommand) async throws
    func disconnect()
}
```

Implement custom `encode(to:)` with the exact snake_case `type` values. Make `MahjongRealtimeClient.send(_:)` accept this enum. Add `session: URLSession` injection to `MahjongScoreService.init` and replace the fallback settlement body with one direct request:

```swift
try await post(
    path: "rooms/\(code.uppercased())/settle",
    body: MahjongSettleRoomRequest(multiplier: multiplier),
    bearerToken: memberToken
)
```

Define `MahjongScoreServicing` and `MahjongRealtimeConnecting` with the exact methods already used by `MahjongScoreViewModel`, make the concrete service/client conform, and create test doubles with deterministic captured commands and callback triggers. The realtime fake must expose `emitSnapshot(_:)`, `emitStatus(_:)`, and `emitError(_:)` so Task 6 can drive every state without a network.

- [ ] **Step 5: 运行 iOS 单元测试和应用构建**

Run:

```bash
xcodebuild -scheme PartyGames-Package -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local test
xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local build
```

Expected: tests PASS and app build ends with `BUILD SUCCEEDED`.

- [ ] **Step 6: 提交 iOS 协议修复**

```bash
git add Package.swift PartyGames/Services/MahjongRoomCommand.swift PartyGames/Services/MahjongRoomDependencies.swift PartyGames/Services/MahjongRealtimeClient.swift PartyGames/Services/MahjongScoreService.swift Tests/PartyGamesUnitTests/URLProtocolStub.swift Tests/PartyGamesUnitTests/MahjongScoreServiceTests.swift Tests/PartyGamesUnitTests/MahjongRoomCommandTests.swift Tests/PartyGamesUnitTests/MahjongRoomTestDoubles.swift
git commit -m "fix: align iOS room protocol"
```

---

### Task 6: ViewModel 权威快照、重连状态与语音去重

**Files:**
- Modify: `PartyGames/Models/MahjongScoreModels.swift`
- Create: `PartyGames/Services/MahjongVoiceAnnouncer.swift`
- Modify: `PartyGames/ViewModels/MahjongScoreViewModel.swift:1-720`
- Create: `Tests/PartyGamesUnitTests/MahjongScoreViewModelTests.swift`

**Interfaces:**
- Consumes: `MahjongRoomSnapshot`、RealtimeClient 状态/错误回调、Service 轮询。
- Produces: `MahjongRoomConnectionPresentation`、`isRoomMutationEnabled`、`isGivingScore`、`applyAuthoritativeSnapshot(_:)` 和新事件语音播报。

- [ ] **Step 1: 写状态与给分失败测试**

Cover these cases with fake service/realtime adapters:

```swift
@Test func networkLossKeepsSnapshotAndShowsReconnect() async {
    let model = makeViewModelWithOwnerSnapshot()
    model.receiveRealtimeStatus(.reconnecting)
    #expect(model.snapshot != nil)
    #expect(model.connectionMessage == "网络连接似乎出现问题，正在重新连接")
    #expect(model.errorMessage != "你已退出房间")
}

@Test func missingSelfInAuthoritativeSnapshotMeansRemoved() async {
    let model = makeViewModelWithOwnerSnapshot()
    model.applyAuthoritativeSnapshot(snapshotWithoutCurrentDevice)
    #expect(model.connectionPresentation == .removed)
    #expect(model.errorMessage == "你已退出房间")
}

@Test func giveScoreDoesNotOptimisticallyMutate() async {
    let model = makeViewModelWithTwoPlayers()
    await model.giveScore(to: "guest-player", amount: 13)
    #expect(model.snapshot?.players.map(\.score) == [0, 0])
    #expect(model.isGivingScore)
}
```

Also test amount bounds, pending reset on next snapshot, owner permissions, table/voice local flags, and no historical speech after reconnect.

- [ ] **Step 2: 运行测试确认当前乐观更新和文案失败**

Run: `xcodebuild -scheme PartyGames-Package -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local test`

Expected: FAIL because current `giveScore` mutates local scores and reconnect uses“同步中（轮询）”。

- [ ] **Step 3: 增加结构化连接展示状态**

Add:

```swift
enum MahjongRoomConnectionPresentation: Equatable, Sendable {
    case connecting, connected, reconnecting, removed, unavailable
}
```

Route every incoming snapshot through:

```swift
func applyAuthoritativeSnapshot(_ next: MahjongRoomSnapshot) {
    if session?.isLocal != true,
       snapshot?.players.contains(where: { $0.deviceId == deviceId }) == true,
       next.players.contains(where: { $0.deviceId == deviceId }) == false {
        connectionPresentation = .removed
        errorMessage = "你已退出房间"
    } else {
        snapshot = next
        isGivingScore = false
    }
}
```

Map `.reconnecting` to the exact network text and disable mutating controls while keeping the last snapshot visible.

- [ ] **Step 4: 移除在线乐观给分与自动重发可能性**

Validate `1...1_000_000`, set `isGivingScore = true`, send once, and do not mutate scores. On send failure clear pending and show friendly network error; on any next authoritative snapshot clear pending. Keep local solo mode’s existing synchronous score updates.

- [ ] **Step 5: 添加语音播报服务**

Create `MahjongVoiceAnnouncer` around `AVSpeechSynthesizer` with:

```swift
func announceNewEvents(previous: MahjongRoomSnapshot?, next: MahjongRoomSnapshot, enabled: Bool)
```

Build a `Set<String>` from prior event IDs; only speak newly appearing paired transfer events. Resolve source from the negative event’s player and target from the positive event’s player, then speak“\(source)给\(target)\(amount)分”。Do nothing on the first snapshot after connect or when disabled.

- [ ] **Step 6: 运行单元测试与应用构建**

Run:

```bash
xcodebuild -scheme PartyGames-Package -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local test
xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local build
```

Expected: all tests PASS and app build succeeds.

- [ ] **Step 7: 提交 ViewModel 状态修复**

```bash
git add PartyGames/Models/MahjongScoreModels.swift PartyGames/Services/MahjongVoiceAnnouncer.swift PartyGames/ViewModels/MahjongScoreViewModel.swift Tests/PartyGamesUnitTests/MahjongScoreViewModelTests.swift
git commit -m "fix: restore multiplayer room state safely"
```

---

### Task 7: iOS 26 Liquid Glass 工具栏、邀请 sheet 和给分小框

**Files:**
- Create: `PartyGames/Design/RoomLiquidGlassControls.swift`
- Create: `PartyGames/Views/components/MahjongRoomToolbar.swift`
- Create: `PartyGames/Views/components/MahjongInviteSheet.swift`
- Create: `PartyGames/Views/components/MahjongGiveScoreDialog.swift`
- Modify: `PartyGames/Views/components/MahjongScorekeeperView.swift:1-710`

**Interfaces:**
- Consumes: ViewModel 的 `reopenInvite()`、`transferOwner(to:)`、table/voice bindings、`giveScore(to:amount:)` 和权限状态。
- Produces: 已确认的房间页面层级和全部房间按钮的原生 Liquid Glass/触觉反馈。

- [ ] **Step 1: 创建统一 Liquid Glass 控件**

Implement `RoomGlassButton` with two visual levels:

```swift
enum RoomGlassButtonLevel { case regular, prominent }

struct RoomGlassButton<Label: View>: View {
    private let level: RoomGlassButtonLevel
    private let isEnabled: Bool
    private let action: () -> Void
    private let label: Label

    init(
        level: RoomGlassButtonLevel = .regular,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.level = level
        self.isEnabled = isEnabled
        self.action = action
        self.label = label()
    }

    var body: some View {
        Group {
            if level == .prominent {
                Button { HapticService.medium(); action() } label: { label }
                    .buttonStyle(.glassProminent)
            } else {
                Button { HapticService.light(); action() } label: { label }
                    .buttonStyle(.glass)
            }
        }
        .disabled(!isEnabled)
    }
}
```

Create `RoomGlassToggle` using a native `.switch` inside `.glassEffect(.regular.interactive(), in: Capsule())`; call `HapticService.selection()` only when an enabled binding changes.

- [ ] **Step 2: 拆出房间工具栏**

Build `MahjongRoomToolbar` with exactly four controls:

```text
添加玩家：房主可见，点击 viewModel.reopenInvite()。
转让群主：房主可见，Menu 候选仅包含有 deviceId 的活跃真实成员。
台板：每设备本地开关，Liquid Glass switch。
语音播报：每设备本地开关，Liquid Glass switch。
```

Remove multiplayer calls to `addRoomPlayer()`; keep that method only for local solo UI where virtual players are allowed.

When the local table switch is enabled, show a Liquid Glass“给台板”action. It opens the same compact integer dialog with a table target and calls `giveTableScore(amount:)`; remove the fixed“给1/给5”buttons.

- [ ] **Step 3: 创建二维码底部 sheet**

`MahjongInviteSheet` must render the existing `QRCodeView`, the complete `inviteURL.absoluteString`, and a single-tap copy row:

```swift
Button {
    UIPasteboard.general.string = inviteURL.absoluteString
    HapticService.selection()
    copied = true
} label: {
    Label(copied ? "链接已复制" : inviteURL.absoluteString, systemImage: copied ? "checkmark" : "doc.on.doc")
}
.buttonStyle(.glass)
```

Present with `.presentationDetents([.medium])` and `.presentationDragIndicator(.visible)`; do not add a `NavigationLink`.

- [ ] **Step 4: 创建紧凑给分弹框**

Replace the full alert state with an overlay dialog no wider than 320 points. Include target name, integer field, source/target preview, cancel and confirm. Parse without silently replacing invalid values:

```swift
var amount: Int? {
    guard let value = Int(text), (1...1_000_000).contains(value) else { return nil }
    return value
}
```

Use `.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))`; disable confirm while invalid, disconnected, or `isGivingScore`.

- [ ] **Step 5: 统一房间按钮反馈与初始列表**

Replace room toolbar, give buttons, invite actions, detail action, settlement action, dialog actions and room menu triggers with `RoomGlassButton` or native `.buttonStyle(.glass/.glassProminent)`. The player list must render exactly `snapshot.players.filter(\.isActive)`; do not insert placeholder players in the view.

- [ ] **Step 6: 构建并在两个外观验证**

Run:

```bash
xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local build
```

Expected: `BUILD SUCCEEDED` with no availability warnings for Glass APIs.

Launch the simulator and verify light mode, dark mode, and Reduce Motion: no overlap at iPhone 17 Pro size; every enabled room control has native pressed highlight; disabled controls produce no haptic.

- [ ] **Step 7: 提交房间 UI**

```bash
git add PartyGames/Design/RoomLiquidGlassControls.swift PartyGames/Views/components/MahjongRoomToolbar.swift PartyGames/Views/components/MahjongInviteSheet.swift PartyGames/Views/components/MahjongGiveScoreDialog.swift PartyGames/Views/components/MahjongScorekeeperView.swift
git commit -m "feat: refresh multiplayer room experience"
```

---

### Task 8: 全量验证、生产部署和冒烟测试

**Files:**
- Modify: `cloudflare/mahjong-score-worker/README.md`

**Interfaces:**
- Consumes: Tasks 1-7 全部产物。
- Produces: 已部署 Worker、已部署网页加入页、生产创建/加入/结算证据和可运行 iOS build。

- [ ] **Step 1: 运行所有自动验证**

Run:

```bash
cd cloudflare/mahjong-score-worker && npm test && npm run typecheck
cd ../../web/mahjong-join && npm run build
cd ../..
xcodebuild -scheme PartyGames-Package -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local test
xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,id=AAC1CB98-61DA-4A90-8ADB-63CC13D8BAE2' -derivedDataPath .derivedData-local build
```

Expected: Vitest PASS, TypeScript PASS, Vite build PASS, iOS tests PASS, and `BUILD SUCCEEDED`.

- [ ] **Step 2: 核对远程 D1 migrations**

Run: `cd cloudflare/mahjong-score-worker && npm run db:migrate:remote`

Expected: migrations `0001` and `0002` are already applied, with no destructive changes.

- [ ] **Step 3: 部署 Worker**

Run: `cd cloudflare/mahjong-score-worker && npm run deploy`

Expected: Wrangler prints a new version ID for `https://mahjong-score-worker.d03054144.workers.dev`.

- [ ] **Step 4: 部署网页加入页**

Run:

```bash
cd web/mahjong-join
npx netlify deploy --prod --dir=dist
```

Expected: Netlify reports the production URL `https://party-games-mahjong-join.netlify.app` and deploy state `ready`.

- [ ] **Step 5: 执行生产 HTTP 冒烟测试**

Run from the repository root:

```bash
OWNER_ID="smoke-owner-$(date +%s)"
CREATE_BODY=$(jq -nc --arg deviceId "$OWNER_ID" '{deviceId: $deviceId, displayName: "房主", title: "部署验证", mode: "multiplayer", startingScore: 0, players: [{name: "不应出现"}]}')
CREATE=$(curl -fsS -X POST 'https://mahjong-score-worker.d03054144.workers.dev/rooms' -H 'content-type: application/json' --data "$CREATE_BODY")
CODE=$(printf '%s' "$CREATE" | jq -r '.snapshot.room.code')
TOKEN=$(printf '%s' "$CREATE" | jq -r '.memberToken')
test "$(printf '%s' "$CREATE" | jq '.snapshot.players | length')" = "1"
GUEST_ID="smoke-guest-$(date +%s)"
JOIN_BODY=$(jq -nc --arg deviceId "$GUEST_ID" '{deviceId: $deviceId, displayName: "客人"}')
JOIN=$(curl -fsS -X POST "https://party-games-mahjong-join.netlify.app/api/rooms/$CODE/join" -H 'content-type: application/json' --data "$JOIN_BODY")
test "$(printf '%s' "$JOIN" | jq '.snapshot.players | length')" = "2"
SETTLED=$(curl -fsS -X POST "https://mahjong-score-worker.d03054144.workers.dev/rooms/$CODE/settle" -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' --data '{"multiplier":2}')
test "$(printf '%s' "$SETTLED" | jq -r '.snapshot.room.status')" = "ended"
```

Expected: every `curl` and `test` exits 0; create has one owner, proxy join has two players, and settle returns `ended`.

- [ ] **Step 6: 手工双端验证**

On iPhone simulator/device plus the deployed web page, verify in order:

```text
创建多人房间 -> 初始只有房主 -> 添加玩家打开底部二维码 sheet -> 点击链接复制
扫码加入 -> 第二名玩家实时出现 -> 给 13 分 -> 双方变为 -13/+13 -> 台板给 7 分
打开语音播报 -> 新给分只播报一次 -> 转让群主 -> 旧房主失去结算权限
断网 -> 保留页面并显示重连 -> 恢复网络 -> 快照恢复
新群主以 2 倍结算 -> 显示胜负与倍率分 -> 旧二维码显示房间已结束
```

- [ ] **Step 7: 更新部署说明并提交**

Document the authoritative `/settle` route, production URLs, and verification commands in the Worker README.

```bash
git add cloudflare/mahjong-score-worker/README.md
git commit -m "docs: record multiplayer deployment checks"
```

---

## Final Review Checklist

- [ ] `git status --short` contains no accidental generated files, secrets, `.env`, `.superpowers`, `node_modules`, or DerivedData changes staged for commit.
- [ ] All Worker tests exercise the production Worker, not only the legacy Node server.
- [ ] Worker and iOS use exactly the same WS command names and field names.
- [ ] Multiplayer room creation ignores extra player drafts and names the owner from `displayName`.
- [ ] Give/table updates remain zero-sum and write two events atomically.
- [ ] `/settle` is owner-only and persists multiplier, result, multiplier score and end time.
- [ ] Network loss, removed membership and ended room have distinct user-visible states.
- [ ] QR and copied URL are identical HTTPS links and can be reopened while active.
- [ ] Every room button and switch has native iOS 26 Liquid Glass visual feedback and the specified haptic level.
- [ ] Production Worker and Netlify deploys pass create/join/settle smoke tests.
