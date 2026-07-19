import { createMemberToken, readBearerToken, verifyMemberToken } from "./auth";
import { HttpError, errorResponse, jsonResponse, optionalString, readJson, requireString } from "./http";
import type { Env, MemberRow, PlayerRow, RoomRow, RoomSnapshot, ScoreEventRow } from "./types";

const DEFAULT_SEATS = ["east", "south", "west", "north"];
const MAX_PLAYERS = 20;
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

interface CreateRoomBody {
  code: string;
  title?: string;
  mode?: "multiplayer" | "solo";
  startingScore?: number;
  deviceId?: string;
  displayName?: string;
  players?: Array<{ name?: string; seat?: string }>;
}

interface PlayerInput {
  name?: string;
  seat?: string;
}

interface JoinRoomBody {
  deviceId?: string;
  displayName?: string;
}

interface SettleRoomBody {
  multiplier?: number;
}

interface MutationMessage {
  operationId?: string;
}

interface AdjustScoreMessage extends MutationMessage {
  type: "adjust_score";
  playerId: string;
  delta: number;
  reason?: string;
}

interface RenamePlayerMessage extends MutationMessage {
  type: "rename_player";
  playerId: string;
  name: string;
}

interface GiveScoreMessage extends MutationMessage {
  type: "give_score";
  targetPlayerId: string;
  amount: number;
  reason?: string;
}

interface TableScoreMessage extends MutationMessage {
  type: "table_score";
  amount: number;
}

interface TransferOwnerMessage extends MutationMessage {
  type: "transfer_owner";
  targetDeviceId: string;
}

interface RemovePlayerMessage extends MutationMessage {
  type: "remove_player";
  playerId: string;
}

interface AddPlayerMessage extends MutationMessage {
  type: "add_player";
  name: string;
}

type ClientMessage =
  | AdjustScoreMessage
  | GiveScoreMessage
  | RenamePlayerMessage
  | TableScoreMessage
  | TransferOwnerMessage
  | RemovePlayerMessage
  | AddPlayerMessage
  | { type: "ping" };

interface WebSocketAttachment {
  roomId: string;
  memberId: string;
  deviceId: string;
}

export class MahjongRoomObject implements DurableObject {
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    return this.runExclusive(() => this.handleFetch(request));
  }

  private async handleFetch(request: Request): Promise<Response> {
    try {
      if (request.headers.get("upgrade")?.toLowerCase() === "websocket") {
        return await this.handleWebSocket(request);
      }

      const url = new URL(request.url);

      switch (url.pathname) {
        case "/create":
          return await this.handleCreate(request);
        case "/join":
          return await this.handleJoin(request);
        case "/snapshot":
          return jsonResponse(await this.getSnapshotByRequest(request));
        case "/end":
          return await this.handleEnd(request);
        case "/settle":
          return await this.handleSettle(request);
        default:
          throw new HttpError(404, "Not found");
      }
    } catch (error) {
      return errorResponse(error);
    }
  }

  async webSocketMessage(webSocket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    await this.runExclusive(() => this.handleWebSocketMessage(webSocket, message));
  }

  private async handleWebSocketMessage(webSocket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    let attachment: WebSocketAttachment | undefined;
    let operationId: string | undefined;
    try {
      attachment = this.readAttachment(webSocket);
      const data = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message)) as ClientMessage;
      operationId = "operationId" in data ? optionalString(data.operationId) : undefined;

      if (data.type === "ping") {
        webSocket.send(JSON.stringify({ type: "pong" }));
        return;
      }

      await this.requireActiveMember(attachment);

      if (data.type === "adjust_score") {
        await this.adjustScore(attachment, data);
        return;
      }

      if (data.type === "give_score") {
        await this.giveScore(attachment, data);
        return;
      }

      if (data.type === "table_score") {
        await this.tableScore(attachment, data);
        return;
      }

      if (data.type === "transfer_owner") {
        await this.transferOwner(attachment, data);
        return;
      }

      if (data.type === "remove_player") {
        await this.removePlayer(attachment, data);
        return;
      }

      if (data.type === "add_player") {
        await this.addPlayer(attachment, data);
        return;
      }

      if (data.type === "rename_player") {
        await this.renamePlayer(attachment, data);
        return;
      }

      throw new HttpError(400, "Unsupported message type");
    } catch (error) {
      webSocket.send(
        JSON.stringify({
          type: "error",
          error: error instanceof Error ? error.message : "Unknown error",
          operationId,
          actorDeviceId: attachment?.deviceId,
        }),
      );
    }
  }

  async webSocketClose(): Promise<void> {}

  async webSocketError(): Promise<void> {}

  private runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.mutationQueue.then(operation, operation);
    this.mutationQueue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }

  private async handleCreate(request: Request): Promise<Response> {
    const body = await readJson<CreateRoomBody>(request);
    const code = requireString(body.code, "code");
    const ownerDeviceId = requireString(body.deviceId, "deviceId");
    const displayName = optionalString(body.displayName) ?? "Player";
    const title = optionalString(body.title) ?? "Mahjong Room";
    const mode = this.normalizeMode(body.mode);
    const startingScore = this.normalizeStartingScore(body.startingScore);
    const roomId = crypto.randomUUID();
    const memberId = crypto.randomUUID();
    const players =
      mode === "multiplayer"
        ? [this.normalizeOwnerPlayer(roomId, ownerDeviceId, displayName, startingScore)]
        : this.normalizePlayers(body.players, startingScore, roomId, ownerDeviceId);

    const existing = await this.env.DB.prepare("SELECT id FROM mahjong_rooms WHERE code = ?").bind(code).first<{ id: string }>();

    if (existing) {
      throw new HttpError(409, "Room code already exists");
    }

    await this.env.DB.batch([
      this.env.DB.prepare(
        `INSERT INTO mahjong_rooms (id, code, title, status, mode, starting_score, owner_device_id)
         VALUES (?, ?, ?, 'active', ?, ?, ?)`,
      ).bind(roomId, code, title, mode, startingScore, ownerDeviceId),
      this.env.DB.prepare(
        `INSERT INTO mahjong_room_members (id, room_id, device_id, display_name, role)
         VALUES (?, ?, ?, ?, 'owner')`,
      ).bind(memberId, roomId, ownerDeviceId, displayName),
      ...players.map((player) =>
        this.env.DB.prepare(
          `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        ).bind(player.id, player.room_id, player.name, player.device_id ?? null, player.seat, player.score, player.sort_order),
      ),
    ]);

    return jsonResponse({
      memberToken: await this.createToken(roomId, memberId, ownerDeviceId),
      snapshot: await this.getSnapshotByRoomId(roomId),
    });
  }

  private async handleJoin(request: Request): Promise<Response> {
    const body = await readJson<JoinRoomBody>(request);
    const deviceId = requireString(body.deviceId, "deviceId");
    const displayName = optionalString(body.displayName) ?? "Player";
    const room = await this.getRoomByCodeFromRequest(request);

    const existingMember = await this.env.DB.prepare(
      "SELECT * FROM mahjong_room_members WHERE room_id = ? AND device_id = ?",
    )
      .bind(room.id, deviceId)
      .first<MemberRow>();

    if (existingMember) {
      if (!existingMember.is_active) {
        throw new HttpError(403, "Membership was removed");
      }

      const payload = await verifyMemberToken(this.env, readBearerToken(request));
      if (payload.roomId !== room.id || payload.memberId !== existingMember.id || payload.deviceId !== deviceId) {
        throw new HttpError(403, "Member token does not match this membership");
      }

      return jsonResponse({
        memberToken: await this.createToken(room.id, existingMember.id, deviceId),
        snapshot: await this.getSnapshotByRoomId(room.id),
      });
    }

    if (room.status !== "active") {
      throw new HttpError(409, "Room is not active");
    }

    const memberId = crypto.randomUUID();
    const count = await this.countPlayers(room.id);
    if (count >= MAX_PLAYERS) {
      throw new HttpError(409, "Room already has the maximum number of players");
    }
    const player = this.normalizeJoinedPlayer(room.id, deviceId, displayName, room.starting_score, count);

    await this.env.DB.batch([
      this.env.DB.prepare(
        `INSERT INTO mahjong_room_members (id, room_id, device_id, display_name, role)
         VALUES (?, ?, ?, ?, 'player')`,
      ).bind(memberId, room.id, deviceId, displayName),
      this.env.DB.prepare(
        `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(player.id, player.room_id, player.name, player.device_id, player.seat, player.score, player.sort_order),
      this.env.DB.prepare("UPDATE mahjong_rooms SET updated_at = datetime('now') WHERE id = ?").bind(room.id),
    ]);

    this.broadcast({ type: "state", snapshot: await this.getSnapshotByRoomId(room.id) });

    return jsonResponse({
      memberToken: await this.createToken(room.id, memberId, deviceId),
      snapshot: await this.getSnapshotByRoomId(room.id),
    });
  }

  private async handleEnd(request: Request): Promise<Response> {
    return this.settleRoom(request, 1);
  }

  private async handleSettle(request: Request): Promise<Response> {
    const body = await readJson<SettleRoomBody>(request);
    return this.settleRoom(request, this.normalizeMultiplier(body.multiplier));
  }

  private async settleRoom(request: Request, multiplier: number): Promise<Response> {
    const payload = await verifyMemberToken(this.env, readBearerToken(request));
    const room = await this.getRoomByCodeFromRequest(request);

    if (payload.roomId !== room.id || payload.deviceId !== room.owner_device_id) {
      throw new HttpError(403, "Only the room owner can settle this room");
    }

    if (room.status !== "active") {
      throw new HttpError(409, "Room is not active");
    }

    const players = await this.env.DB.prepare(
      "SELECT * FROM mahjong_players WHERE room_id = ? AND is_active = 1 ORDER BY sort_order ASC",
    )
      .bind(room.id)
      .all<PlayerRow>();

    await this.env.DB.batch([
      ...players.results.map((player) => {
        const result = player.score > 0 ? "win" : player.score < 0 ? "lose" : "draw";
        return this.env.DB.prepare(
          "UPDATE mahjong_players SET multiplier_score = ?, result = ?, updated_at = datetime('now') WHERE id = ?",
        ).bind(player.score * multiplier, result, player.id);
      }),
      this.env.DB.prepare(
        `UPDATE mahjong_rooms
         SET status = 'ended', multiplier = ?, ended_at = datetime('now'), updated_at = datetime('now')
         WHERE id = ?`,
      ).bind(multiplier, room.id),
    ]);

    const snapshot = await this.getSnapshotByRoomId(room.id);
    this.broadcast({ type: "state", snapshot });

    return jsonResponse({ snapshot });
  }

  private async handleWebSocket(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const payload = await verifyMemberToken(this.env, url.searchParams.get("memberToken"));
    const room = await this.getRoomByCodeFromRequest(request);

    if (payload.roomId !== room.id) {
      throw new HttpError(403, "Token does not belong to this room");
    }

    await this.requireActiveMember({
      roomId: payload.roomId,
      memberId: payload.memberId,
      deviceId: payload.deviceId,
    });

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const attachment: WebSocketAttachment = {
      roomId: payload.roomId,
      memberId: payload.memberId,
      deviceId: payload.deviceId,
    };

    this.state.acceptWebSocket(server);
    server.serializeAttachment(attachment);
    server.send(JSON.stringify({ type: "state", snapshot: await this.getSnapshotByRoomId(room.id) }));

    return new Response(null, { status: 101, webSocket: client });
  }

  private async adjustScore(attachment: WebSocketAttachment, message: AdjustScoreMessage): Promise<void> {
    if (!Number.isInteger(message.delta) || message.delta === 0) {
      throw new HttpError(400, "delta must be a non-zero integer");
    }

    const room = await this.requireActiveRoom(attachment.roomId);
    if ((room.mode ?? "multiplayer") !== "solo") {
      throw new HttpError(400, "Use give_score in multiplayer rooms");
    }

    if (room.owner_device_id !== attachment.deviceId) {
      throw new HttpError(403, "Only the room owner can adjust scores");
    }

    const player = await this.env.DB.prepare("SELECT id FROM mahjong_players WHERE id = ? AND room_id = ? AND is_active = 1")
      .bind(message.playerId, attachment.roomId)
      .first<{ id: string }>();

    if (!player) {
      throw new HttpError(404, "Player not found");
    }

    const eventId = crypto.randomUUID();
    const reason = optionalString(message.reason) ?? null;

    await this.env.DB.batch([
      this.env.DB.prepare(
        `UPDATE mahjong_players
         SET score = score + ?, updated_at = datetime('now')
         WHERE id = ? AND room_id = ? AND is_active = 1`,
      ).bind(message.delta, message.playerId, attachment.roomId),
      this.env.DB.prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, (SELECT score FROM mahjong_players WHERE id = ?))`,
      ).bind(eventId, attachment.roomId, message.playerId, attachment.memberId, message.delta, reason, message.playerId),
      this.env.DB.prepare("UPDATE mahjong_rooms SET updated_at = datetime('now') WHERE id = ?").bind(attachment.roomId),
    ]);

    await this.broadcastMutation(attachment, message);
  }

  private async renamePlayer(attachment: WebSocketAttachment, message: RenamePlayerMessage): Promise<void> {
    const name = requireString(message.name, "name").slice(0, 24);
    const room = await this.requireActiveRoom(attachment.roomId);
    const player = await this.env.DB.prepare(
      "SELECT * FROM mahjong_players WHERE id = ? AND room_id = ? AND is_active = 1",
    )
      .bind(message.playerId, attachment.roomId)
      .first<PlayerRow>();

    if (!player) {
      throw new HttpError(404, "Player not found");
    }

    if (room.owner_device_id !== attachment.deviceId && player.device_id !== attachment.deviceId) {
      throw new HttpError(403, "You can only rename yourself");
    }

    await this.env.DB.prepare(
      `UPDATE mahjong_players
       SET name = ?, updated_at = datetime('now')
       WHERE id = ? AND room_id = ? AND is_active = 1`,
    )
      .bind(name, message.playerId, attachment.roomId)
      .run();

    if (player.device_id) {
      await this.env.DB.prepare(
        "UPDATE mahjong_room_members SET display_name = ? WHERE room_id = ? AND device_id = ? AND is_active = 1",
      )
        .bind(name, attachment.roomId, player.device_id)
        .run();
    }

    await this.broadcastMutation(attachment, message);
  }

  private async giveScore(attachment: WebSocketAttachment, message: GiveScoreMessage): Promise<void> {
    const targetPlayerId = requireString(message.targetPlayerId, "targetPlayerId");
    const amount = this.normalizeScoreAmount(message.amount);
    await this.requireActiveRoom(attachment.roomId);

    const actingPlayer = await this.findActivePlayerForDevice(attachment.roomId, attachment.deviceId);
    if (!actingPlayer) {
      throw new HttpError(404, "Acting player not found");
    }

    const targetPlayer = await this.env.DB.prepare(
      "SELECT id FROM mahjong_players WHERE id = ? AND room_id = ? AND is_active = 1",
    )
      .bind(targetPlayerId, attachment.roomId)
      .first<{ id: string }>();

    if (!targetPlayer) {
      throw new HttpError(404, "Player not found");
    }

    if (targetPlayer.id === actingPlayer.id) {
      throw new HttpError(400, "You cannot give score to yourself");
    }

    const reason = optionalString(message.reason) ?? "给分";
    await this.env.DB.batch([
      this.env.DB.prepare(
        `UPDATE mahjong_players
         SET score = score - ?, updated_at = datetime('now')
         WHERE id = ? AND room_id = ? AND is_active = 1`,
      ).bind(amount, actingPlayer.id, attachment.roomId),
      this.env.DB.prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, (SELECT score FROM mahjong_players WHERE id = ?))`,
      ).bind(crypto.randomUUID(), attachment.roomId, actingPlayer.id, attachment.memberId, -amount, reason, actingPlayer.id),
      this.env.DB.prepare(
        `UPDATE mahjong_players
         SET score = score + ?, updated_at = datetime('now')
         WHERE id = ? AND room_id = ? AND is_active = 1`,
      ).bind(amount, targetPlayer.id, attachment.roomId),
      this.env.DB.prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, (SELECT score FROM mahjong_players WHERE id = ?))`,
      ).bind(crypto.randomUUID(), attachment.roomId, targetPlayer.id, attachment.memberId, amount, reason, targetPlayer.id),
      this.env.DB.prepare("UPDATE mahjong_rooms SET updated_at = datetime('now') WHERE id = ?").bind(attachment.roomId),
    ]);

    await this.broadcastMutation(attachment, message);
  }

  private async tableScore(attachment: WebSocketAttachment, message: TableScoreMessage): Promise<void> {
    const amount = this.normalizeScoreAmount(message.amount);
    await this.requireActiveRoom(attachment.roomId);

    const actingPlayer = await this.findActivePlayerForDevice(attachment.roomId, attachment.deviceId);
    if (!actingPlayer) {
      throw new HttpError(404, "Acting player not found");
    }

    const tablePlayer = await this.env.DB.prepare(
      "SELECT id FROM mahjong_players WHERE room_id = ? AND seat = 'table' AND is_active = 1",
    )
      .bind(attachment.roomId)
      .first<{ id: string }>();
    const tablePlayerId = tablePlayer?.id ?? crypto.randomUUID();
    const playerCount = tablePlayer ? 0 : await this.countPlayers(attachment.roomId);
    const statements = [];

    if (!tablePlayer) {
      statements.push(
        this.env.DB.prepare(
          `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
           VALUES (?, ?, '台板', NULL, 'table', 0, ?)`,
        ).bind(tablePlayerId, attachment.roomId, playerCount),
      );
    }

    statements.push(
      this.env.DB.prepare(
        `UPDATE mahjong_players
         SET score = score - ?, updated_at = datetime('now')
         WHERE id = ? AND room_id = ? AND is_active = 1`,
      ).bind(amount, actingPlayer.id, attachment.roomId),
      this.env.DB.prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, '台板(茶水)', (SELECT score FROM mahjong_players WHERE id = ?))`,
      ).bind(crypto.randomUUID(), attachment.roomId, actingPlayer.id, attachment.memberId, -amount, actingPlayer.id),
      this.env.DB.prepare(
        `UPDATE mahjong_players
         SET score = score + ?, updated_at = datetime('now')
         WHERE id = ? AND room_id = ? AND is_active = 1`,
      ).bind(amount, tablePlayerId, attachment.roomId),
      this.env.DB.prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, '台板(茶水)', (SELECT score FROM mahjong_players WHERE id = ?))`,
      ).bind(crypto.randomUUID(), attachment.roomId, tablePlayerId, attachment.memberId, amount, tablePlayerId),
      this.env.DB.prepare("UPDATE mahjong_rooms SET updated_at = datetime('now') WHERE id = ?").bind(attachment.roomId),
    );

    await this.env.DB.batch(statements);
    await this.broadcastMutation(attachment, message);
  }

  private async transferOwner(attachment: WebSocketAttachment, message: TransferOwnerMessage): Promise<void> {
    const targetDeviceId = requireString(message.targetDeviceId, "targetDeviceId");
    const room = await this.requireActiveRoom(attachment.roomId);

    if (room.owner_device_id !== attachment.deviceId) {
      throw new HttpError(403, "Only the room owner can transfer ownership");
    }

    if (targetDeviceId === attachment.deviceId) {
      throw new HttpError(400, "Target is already the room owner");
    }

    const [targetMember, targetPlayer] = await Promise.all([
      this.env.DB.prepare(
        "SELECT id FROM mahjong_room_members WHERE room_id = ? AND device_id = ? AND is_active = 1",
      )
        .bind(attachment.roomId, targetDeviceId)
        .first<{ id: string }>(),
      this.findActivePlayerForDevice(attachment.roomId, targetDeviceId),
    ]);

    if (!targetMember || !targetPlayer) {
      throw new HttpError(404, "Target must be an active room member");
    }

    await this.env.DB.batch([
      this.env.DB.prepare(
        "UPDATE mahjong_rooms SET owner_device_id = ?, updated_at = datetime('now') WHERE id = ?",
      ).bind(targetDeviceId, attachment.roomId),
      this.env.DB.prepare(
        `UPDATE mahjong_room_members
         SET role = CASE WHEN device_id = ? THEN 'owner' ELSE 'player' END
         WHERE room_id = ? AND device_id IN (?, ?)`,
      ).bind(targetDeviceId, attachment.roomId, attachment.deviceId, targetDeviceId),
    ]);

    await this.broadcastMutation(attachment, message);
  }

  private async removePlayer(attachment: WebSocketAttachment, message: RemovePlayerMessage): Promise<void> {
    const playerId = requireString(message.playerId, "playerId");
    const room = await this.requireActiveRoom(attachment.roomId);
    const player = await this.env.DB.prepare(
      "SELECT * FROM mahjong_players WHERE id = ? AND room_id = ? AND is_active = 1",
    )
      .bind(playerId, attachment.roomId)
      .first<PlayerRow>();

    if (!player) {
      throw new HttpError(404, "Player not found");
    }

    if (!player.device_id) {
      throw new HttpError(400, "Only scanned players can leave or be removed");
    }

    if (player.device_id === room.owner_device_id) {
      throw new HttpError(400, "The room owner cannot be removed");
    }

    if (player.score !== 0) {
      throw new HttpError(409, "Player balance must be zero before removal");
    }

    const isSelf = player.device_id === attachment.deviceId;
    const isOwnerRemoving = room.owner_device_id === attachment.deviceId;
    if (!isSelf && !isOwnerRemoving) {
      throw new HttpError(403, "You can only leave yourself");
    }

    await this.env.DB.batch([
      this.env.DB.prepare(
        "UPDATE mahjong_players SET is_active = 0, updated_at = datetime('now') WHERE id = ?",
      ).bind(player.id),
      this.env.DB.prepare(
        "UPDATE mahjong_room_members SET is_active = 0 WHERE room_id = ? AND device_id = ?",
      ).bind(attachment.roomId, player.device_id),
      this.env.DB.prepare("UPDATE mahjong_rooms SET updated_at = datetime('now') WHERE id = ?").bind(attachment.roomId),
    ]);

    await this.broadcastMutation(attachment, message);
    this.closeSocketsForDevice(player.device_id);
  }

  private async addPlayer(attachment: WebSocketAttachment, message: AddPlayerMessage): Promise<void> {
    const name = requireString(message.name, "name").slice(0, 24);
    const room = await this.requireActiveRoom(attachment.roomId);

    if ((room.mode ?? "multiplayer") !== "solo" || room.owner_device_id !== attachment.deviceId) {
      throw new HttpError(403, "Only solo-room owners can add players");
    }

    const playerCount = await this.countPlayers(attachment.roomId);
    if (playerCount >= MAX_PLAYERS) {
      throw new HttpError(400, "Room already has the maximum number of players");
    }

    await this.env.DB.batch([
      this.env.DB.prepare(
        `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
         VALUES (?, ?, ?, NULL, NULL, ?, ?)`,
      ).bind(crypto.randomUUID(), attachment.roomId, name, room.starting_score, playerCount),
      this.env.DB.prepare("UPDATE mahjong_rooms SET updated_at = datetime('now') WHERE id = ?").bind(attachment.roomId),
    ]);

    await this.broadcastMutation(attachment, message);
  }

  private async broadcastMutation(attachment: WebSocketAttachment, message: MutationMessage): Promise<void> {
    this.broadcast({
      type: "state",
      snapshot: await this.getSnapshotByRoomId(attachment.roomId),
      operationId: optionalString(message.operationId),
      actorDeviceId: attachment.deviceId,
    });
  }

  private broadcast(message: unknown): void {
    const serialized = JSON.stringify(message);

    for (const webSocket of this.state.getWebSockets()) {
      try {
        webSocket.send(serialized);
      } catch {
        try {
          webSocket.close(1011, "Snapshot delivery failed");
        } catch {}
      }
    }
  }

  private closeSocketsForDevice(deviceId: string): void {
    for (const webSocket of this.state.getWebSockets()) {
      try {
        if (this.readAttachment(webSocket).deviceId === deviceId) {
          webSocket.close(1008, "Membership removed");
        }
      } catch {
        try {
          webSocket.close(1008, "Membership removed");
        } catch {}
      }
    }
  }

  private readAttachment(webSocket: WebSocket): WebSocketAttachment {
    const attachment = webSocket.deserializeAttachment() as WebSocketAttachment | undefined;

    if (!attachment) {
      throw new HttpError(401, "Missing websocket attachment");
    }

    return attachment;
  }

  private async getSnapshotByRequest(request: Request): Promise<RoomSnapshot> {
    const room = await this.getRoomByCodeFromRequest(request);
    return this.getSnapshotByRoomId(room.id);
  }

  private async getRoomByCodeFromRequest(request: Request): Promise<RoomRow> {
    const code = requireString(new URL(request.url).searchParams.get("code"), "code");
    const room = await this.env.DB.prepare("SELECT * FROM mahjong_rooms WHERE code = ?").bind(code).first<RoomRow>();

    if (!room) {
      throw new HttpError(404, "Room not found");
    }

    return room;
  }

  private async getSnapshotByRoomId(roomId: string): Promise<RoomSnapshot> {
    const room = await this.env.DB.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").bind(roomId).first<RoomRow>();

    if (!room) {
      throw new HttpError(404, "Room not found");
    }

    const players = await this.env.DB.prepare(
      `SELECT * FROM mahjong_players WHERE room_id = ? AND is_active = 1 ORDER BY sort_order ASC`,
    )
      .bind(roomId)
      .all<PlayerRow>();
    const events = await this.env.DB.prepare(
      `SELECT * FROM mahjong_score_events WHERE room_id = ? ORDER BY created_at DESC LIMIT 50`,
    )
      .bind(roomId)
      .all<ScoreEventRow>();

    return {
      room: {
        id: room.id,
        code: room.code,
        title: room.title,
        status: room.status,
        mode: room.mode ?? "multiplayer",
        startingScore: room.starting_score,
        ownerDeviceId: room.owner_device_id,
        multiplier: room.multiplier ?? 1,
        createdAt: room.created_at,
        endedAt: room.ended_at,
        updatedAt: room.updated_at,
      },
      players: players.results.map((player) => ({
        id: player.id,
        name: player.name,
        deviceId: player.device_id,
        seat: player.seat,
        score: player.score,
        multiplierScore: player.multiplier_score ?? player.score,
        result: player.result ?? null,
        sortOrder: player.sort_order,
        isActive: player.is_active === 1,
      })),
      recentEvents: events.results.map((event) => ({
        id: event.id,
        playerId: event.player_id,
        actorMemberId: event.actor_member_id,
        delta: event.delta,
        reason: event.reason,
        scoreAfter: event.score_after,
        createdAt: event.created_at,
      })),
    };
  }

  private normalizeStartingScore(value: unknown): number {
    if (value === undefined) {
      return 0;
    }

    if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 1000000) {
      throw new HttpError(400, "startingScore must be an integer between 0 and 1000000");
    }

    return value;
  }

  private normalizeScoreAmount(value: unknown): number {
    if (typeof value !== "number" || !Number.isInteger(value) || value <= 0 || value > 1_000_000) {
      throw new HttpError(400, "amount must be an integer between 1 and 1000000");
    }

    return value;
  }

  private normalizeMultiplier(value: unknown): number {
    if (value === undefined) {
      return 1;
    }

    if (typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > 1_000_000) {
      throw new HttpError(400, "multiplier must be a positive number no greater than 1000000");
    }

    return value;
  }

  private normalizeMode(value: unknown): "multiplayer" | "solo" {
    if (value === undefined) {
      return "multiplayer";
    }

    if (value === "multiplayer" || value === "solo") {
      return value;
    }

    throw new HttpError(400, "mode must be multiplayer or solo");
  }

  private normalizeOwnerPlayer(roomId: string, deviceId: string, displayName: string, score: number): PlayerRow {
    return {
      id: crypto.randomUUID(),
      room_id: roomId,
      name: displayName,
      device_id: deviceId,
      seat: null,
      score,
      multiplier_score: score,
      result: null,
      sort_order: 0,
      is_active: 1,
      created_at: "",
      updated_at: "",
    };
  }

  private normalizePlayers(
    players: CreateRoomBody["players"],
    startingScore: number,
    roomId: string,
    ownerDeviceId?: string,
  ): PlayerRow[] {
    const rawPlayers: PlayerInput[] =
      Array.isArray(players) && players.length > 0 ? players.slice(0, MAX_PLAYERS) : DEFAULT_SEATS.map((seat) => ({ seat }));

    while (rawPlayers.length < 4) {
      rawPlayers.push({ seat: DEFAULT_SEATS[rawPlayers.length] });
    }

    return rawPlayers.map((player, index) => ({
      id: crypto.randomUUID(),
      room_id: roomId,
      name: optionalString(player.name) ?? `Player ${index + 1}`,
      device_id: index === 0 ? (ownerDeviceId ?? null) : null,
      seat: optionalString(player.seat) ?? DEFAULT_SEATS[index] ?? null,
      score: startingScore,
      sort_order: index,
      is_active: 1,
      created_at: "",
      updated_at: "",
    }));
  }

  private normalizeJoinedPlayer(
    roomId: string,
    deviceId: string,
    displayName: string,
    startingScore: number,
    sortOrder: number,
  ): PlayerRow {
    const name = optionalString(displayName) ?? `玩家${sortOrder + 1}`;

    return {
      id: crypto.randomUUID(),
      room_id: roomId,
      name: name.startsWith("Player") ? `玩家${sortOrder + 1}` : name,
      device_id: deviceId,
      seat: null,
      score: startingScore,
      sort_order: sortOrder,
      is_active: 1,
      created_at: "",
      updated_at: "",
    };
  }

  private async countPlayers(roomId: string): Promise<number> {
    const row = await this.env.DB.prepare("SELECT COUNT(*) AS count FROM mahjong_players WHERE room_id = ?").bind(roomId).first<{ count: number }>();
    return row?.count ?? 0;
  }

  private async findActivePlayerForDevice(roomId: string, deviceId: string): Promise<{ id: string } | null> {
    return this.env.DB.prepare("SELECT id FROM mahjong_players WHERE room_id = ? AND device_id = ? AND is_active = 1")
      .bind(roomId, deviceId)
      .first<{ id: string }>();
  }

  private async requireActiveRoom(roomId: string): Promise<RoomRow> {
    const room = await this.env.DB.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").bind(roomId).first<RoomRow>();

    if (!room) {
      throw new HttpError(404, "Room not found");
    }

    if (room.status !== "active") {
      throw new HttpError(409, "Room is not active");
    }

    return room;
  }

  private async requireActiveMember(attachment: WebSocketAttachment): Promise<void> {
    const member = await this.env.DB.prepare(
      "SELECT id FROM mahjong_room_members WHERE id = ? AND room_id = ? AND device_id = ? AND is_active = 1",
    )
      .bind(attachment.memberId, attachment.roomId, attachment.deviceId)
      .first<{ id: string }>();

    if (!member) {
      throw new HttpError(403, "Room membership is no longer active");
    }
  }

  private createToken(roomId: string, memberId: string, deviceId: string): Promise<string> {
    return createMemberToken(this.env, {
      roomId,
      memberId,
      deviceId,
      exp: Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS,
    });
  }
}
