import { createServer, type Server } from "node:http";
import crypto from "node:crypto";
import Database from "better-sqlite3";
import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import { customAlphabet } from "nanoid";
import { WebSocketServer, type WebSocket } from "ws";
import { migrate } from "./schema.js";
import { createMemberToken, httpError, verifyMemberToken } from "./tokens.js";

const DEFAULT_SEATS = ["east", "south", "west", "north"];
const MAX_PLAYERS = 20;
const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const createRoomCode = customAlphabet(ROOM_CODE_ALPHABET, 6);
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

export interface MahjongSyncServerOptions {
  databasePath: string;
  memberTokenSecret: string;
  port: number;
}

export interface MahjongSyncServer {
  url: string;
  close: () => Promise<void>;
}

interface CreateRoomBody {
  title?: string;
  mode?: "multiplayer" | "solo";
  startingScore?: number;
  deviceId?: string;
  displayName?: string;
  players?: Array<{ name?: string; seat?: string }>;
}

interface JoinRoomBody {
  deviceId?: string;
  displayName?: string;
}

interface RoomRow {
  id: string;
  code: string;
  title: string;
  status: string;
  mode: string;
  starting_score: number;
  owner_device_id: string;
  multiplier: number;
  created_at: string;
  ended_at: string | null;
  updated_at: string;
}

interface PlayerRow {
  id: string;
  room_id: string;
  name: string;
  device_id: string | null;
  seat: string | null;
  score: number;
  multiplier_score: number;
  result: string | null;
  sort_order: number;
  is_active: number;
}

interface MemberRow {
  id: string;
  room_id: string;
  device_id: string;
  display_name: string;
  role: string;
}

interface ScoreEventRow {
  id: string;
  room_id: string;
  player_id: string;
  actor_member_id: string;
  delta: number;
  reason: string | null;
  score_after: number;
  created_at: string;
}

interface SocketAttachment {
  roomId: string;
  memberId: string;
  deviceId: string;
}

export async function createMahjongSyncServer(options: MahjongSyncServerOptions): Promise<MahjongSyncServer> {
  const database = new Database(options.databasePath);
  database.pragma("foreign_keys = ON");
  migrate(database);

  const app = express();
  const httpServer = createServer(app);
  const socketsByRoom = new Map<string, Set<WebSocket>>();

  app.use(cors());
  app.use(express.json({ limit: "64kb" }));

  app.get("/health", (_request, response) => {
    response.json({ ok: true });
  });

  app.get("/history", (request, response, next) => {
    try {
      const deviceId = requireString(request.query.deviceId, "deviceId");
      const rows = database
        .prepare(
          `SELECT DISTINCT rooms.*
           FROM mahjong_rooms rooms
           INNER JOIN mahjong_room_members members ON members.room_id = rooms.id
           WHERE members.device_id = ?
           ORDER BY rooms.updated_at DESC
           LIMIT 50`,
        )
        .all(deviceId) as RoomRow[];

      response.json({
        rooms: rows.map((room) => roomInfo(room)),
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/rooms", (request, response, next) => {
    try {
      const body = request.body as CreateRoomBody;
      const code = createUniqueRoomCode(database);
      const roomId = crypto.randomUUID();
      const memberId = crypto.randomUUID();
      const ownerDeviceId = requireString(body.deviceId, "deviceId");
      const displayName = optionalString(body.displayName) ?? "Player";
      const title = optionalString(body.title) ?? "Mahjong Room";
      const mode = normalizeMode(body.mode);
      const startingScore = normalizeStartingScore(body.startingScore);
      const players = normalizePlayers(body.players, startingScore, roomId);

      const createRoom = database.transaction(() => {
        database
          .prepare(
            `INSERT INTO mahjong_rooms (id, code, title, status, mode, starting_score, owner_device_id)
             VALUES (?, ?, ?, 'active', ?, ?, ?)`,
          )
          .run(roomId, code, title, mode, startingScore, ownerDeviceId);
        database
          .prepare(
            `INSERT INTO mahjong_room_members (id, room_id, device_id, display_name, role)
             VALUES (?, ?, ?, ?, 'owner')`,
          )
          .run(memberId, roomId, ownerDeviceId, displayName);

        const insertPlayer = database.prepare(
          `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        );
        for (const [index, player] of players.entries()) {
          insertPlayer.run(player.id, roomId, player.name, index === 0 ? ownerDeviceId : null, player.seat, player.score, player.sortOrder);
        }
      });

      createRoom();
      response.json({
        memberToken: createToken(options.memberTokenSecret, roomId, memberId, ownerDeviceId),
        snapshot: getSnapshot(database, roomId),
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/rooms/:code/join", (request, response, next) => {
    try {
      const body = request.body as JoinRoomBody;
      const deviceId = requireString(body.deviceId, "deviceId");
      const displayName = optionalString(body.displayName) ?? "Player";
      const room = getRoomByCode(database, request.params.code);
      let member = database
        .prepare("SELECT * FROM mahjong_room_members WHERE room_id = ? AND device_id = ?")
        .get(room.id, deviceId) as MemberRow | undefined;

      if (!member) {
        const memberId = crypto.randomUUID();
        const joinRoom = database.transaction(() => {
          database
            .prepare(
              `INSERT INTO mahjong_room_members (id, room_id, device_id, display_name, role)
               VALUES (?, ?, ?, ?, 'player')`,
            )
            .run(memberId, room.id, deviceId, displayName);
          createJoinedPlayer(database, room.id, deviceId, displayName, room.starting_score);
          database.prepare("UPDATE mahjong_rooms SET updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(room.id);
        });
        joinRoom();
        member = database.prepare("SELECT * FROM mahjong_room_members WHERE id = ?").get(memberId) as MemberRow | undefined;
        broadcast(socketsByRoom, room.id, { type: "state", snapshot: getSnapshot(database, room.id) });
      }

      if (!member) {
        throw httpError(500, "Failed to join room");
      }

      response.json({
        memberToken: createToken(options.memberTokenSecret, room.id, member.id, deviceId),
        snapshot: getSnapshot(database, room.id),
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/rooms/:code", (request, response, next) => {
    try {
      const room = getRoomByCode(database, request.params.code);
      response.json(getSnapshot(database, room.id));
    } catch (error) {
      next(error);
    }
  });

  app.post("/rooms/:code/settle", (request, response, next) => {
    try {
      const room = getRoomByCode(database, request.params.code);
      const payload = verifyMemberToken(options.memberTokenSecret, readBearerToken(request));
      if (payload.roomId !== room.id || payload.deviceId !== room.owner_device_id) {
        throw httpError(403, "Only the room owner can settle this room");
      }

      const multiplier = normalizeMultiplier((request.body as { multiplier?: unknown }).multiplier);
      settleRoom(database, room.id, multiplier);
      const snapshot = getSnapshot(database, room.id);
      broadcast(socketsByRoom, room.id, { type: "state", snapshot });
      response.json({ snapshot });
    } catch (error) {
      next(error);
    }
  });

  app.post("/rooms/:code/dismiss", (request, response, next) => {
    try {
      const room = getRoomByCode(database, request.params.code);
      const payload = verifyMemberToken(options.memberTokenSecret, readBearerToken(request));
      if (payload.roomId !== room.id) {
        throw httpError(403, "Token does not belong to this room");
      }

      const dismiss = database.transaction(() => {
        if (room.status === "active" && room.owner_device_id === payload.deviceId) {
          settleRoom(database, room.id, room.multiplier > 0 ? room.multiplier : 1);
        }
        database
          .prepare("DELETE FROM mahjong_room_members WHERE room_id = ? AND device_id = ?")
          .run(room.id, payload.deviceId);
      });
      dismiss();

      if (room.status === "active") {
        const snapshot = getSnapshot(database, room.id);
        broadcast(socketsByRoom, room.id, { type: "state", snapshot });
      }

      response.json({ ok: true });
    } catch (error) {
      next(error);
    }
  });

  app.use((error: unknown, _request: Request, response: Response, _next: NextFunction) => {
    const status = typeof error === "object" && error && "status" in error ? Number(error.status) : 500;
    const message = error instanceof Error ? error.message : "Internal server error";
    response.status(status || 500).json({ error: status === 500 ? "Internal server error" : message });
  });

  const wss = new WebSocketServer({ noServer: true });
  httpServer.on("upgrade", (request, socket, head) => {
    try {
      const url = new URL(request.url ?? "", "http://localhost");
      const match = url.pathname.match(/^\/rooms\/([^/]+)\/ws$/);
      if (!match) {
        socket.destroy();
        return;
      }

      const room = getRoomByCode(database, match[1]);
      const payload = verifyMemberToken(options.memberTokenSecret, url.searchParams.get("memberToken"));
      if (payload.roomId !== room.id) {
        throw httpError(403, "Token does not belong to this room");
      }
      const member = database
        .prepare("SELECT id FROM mahjong_room_members WHERE id = ? AND room_id = ? AND device_id = ?")
        .get(payload.memberId, payload.roomId, payload.deviceId);
      if (!member) {
        throw httpError(403, "Room membership is no longer active");
      }

      wss.handleUpgrade(request, socket, head, (webSocket) => {
        const attachment: SocketAttachment = {
          roomId: payload.roomId,
          memberId: payload.memberId,
          deviceId: payload.deviceId,
        };
        attachSocket(database, socketsByRoom, webSocket, attachment);
      });
    } catch {
      socket.destroy();
    }
  });

  await new Promise<void>((resolve) => {
    httpServer.listen(options.port, "0.0.0.0", resolve);
  });

  const address = httpServer.address();
  if (!address || typeof address === "string") {
    throw new Error("Failed to determine server address");
  }

  return {
    url: `http://127.0.0.1:${address.port}`,
    close: () =>
      new Promise<void>((resolve, reject) => {
        wss.close();
        database.close();
        httpServer.close((error) => (error ? reject(error) : resolve()));
      }),
  };
}

function attachSocket(
  database: Database.Database,
  socketsByRoom: Map<string, Set<WebSocket>>,
  webSocket: WebSocket,
  attachment: SocketAttachment,
): void {
  let sockets = socketsByRoom.get(attachment.roomId);
  if (!sockets) {
    sockets = new Set();
    socketsByRoom.set(attachment.roomId, sockets);
  }
  sockets.add(webSocket);

  webSocket.send(JSON.stringify({ type: "state", snapshot: getSnapshot(database, attachment.roomId) }));
  webSocket.on("message", (raw) => {
    try {
      const message = JSON.parse(String(raw)) as {
        type?: string;
        playerId?: string;
        delta?: number;
        reason?: string;
        name?: string;
        targetDeviceId?: string;
        targetPlayerId?: string;
        amount?: number;
      };

      if (message.type === "ping") {
        webSocket.send(JSON.stringify({ type: "pong" }));
        return;
      }

      if (message.type === "adjust_score") {
        adjustScore(database, attachment, message);
        broadcast(socketsByRoom, attachment.roomId, { type: "state", snapshot: getSnapshot(database, attachment.roomId) });
        return;
      }

      if (message.type === "give_score") {
        giveScore(database, attachment, message);
        broadcast(socketsByRoom, attachment.roomId, { type: "state", snapshot: getSnapshot(database, attachment.roomId) });
        return;
      }

      if (message.type === "rename_player") {
        renamePlayer(database, attachment, message);
        broadcast(socketsByRoom, attachment.roomId, { type: "state", snapshot: getSnapshot(database, attachment.roomId) });
        return;
      }

      if (message.type === "add_player") {
        addPlayer(database, attachment, message);
        broadcast(socketsByRoom, attachment.roomId, { type: "state", snapshot: getSnapshot(database, attachment.roomId) });
        return;
      }

      if (message.type === "remove_player") {
        removePlayer(database, attachment, message);
        broadcast(socketsByRoom, attachment.roomId, { type: "state", snapshot: getSnapshot(database, attachment.roomId) });
        return;
      }

      if (message.type === "table_score") {
        tableScore(database, attachment, message);
        broadcast(socketsByRoom, attachment.roomId, { type: "state", snapshot: getSnapshot(database, attachment.roomId) });
        return;
      }

      if (message.type === "transfer_owner") {
        transferOwner(database, attachment, message);
        broadcast(socketsByRoom, attachment.roomId, { type: "state", snapshot: getSnapshot(database, attachment.roomId) });
        return;
      }

      throw httpError(400, "Unsupported message type");
    } catch (error) {
      webSocket.send(JSON.stringify({ type: "error", error: error instanceof Error ? error.message : "Unknown error" }));
    }
  });
  webSocket.on("close", () => {
    sockets?.delete(webSocket);
  });
}

function renamePlayer(
  database: Database.Database,
  attachment: SocketAttachment,
  message: { playerId?: string; name?: string },
): void {
  const playerId = requireString(message.playerId, "playerId");
  const name = requireString(message.name, "name").slice(0, 24);
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(attachment.roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }

  const player = database.prepare("SELECT * FROM mahjong_players WHERE id = ? AND room_id = ?").get(playerId, attachment.roomId) as
    | PlayerRow
    | undefined;
  if (!player) {
    throw httpError(404, "Player not found");
  }
  if (room.owner_device_id !== attachment.deviceId && player.device_id !== attachment.deviceId) {
    throw httpError(403, "You can only rename yourself");
  }

  database.prepare("UPDATE mahjong_players SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(name, playerId);
  if (player.device_id) {
    database
      .prepare("UPDATE mahjong_room_members SET display_name = ? WHERE room_id = ? AND device_id = ?")
      .run(name, attachment.roomId, player.device_id);
  }
}

function removePlayer(
  database: Database.Database,
  attachment: SocketAttachment,
  message: { playerId?: string },
): void {
  const playerId = requireString(message.playerId, "playerId");
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(attachment.roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }
  if (room.status !== "active") {
    throw httpError(400, "Room is not active");
  }

  const player = database
    .prepare("SELECT * FROM mahjong_players WHERE id = ? AND room_id = ? AND is_active = 1")
    .get(playerId, attachment.roomId) as PlayerRow | undefined;
  if (!player) {
    throw httpError(404, "Player not found");
  }
  if (!player.device_id) {
    throw httpError(400, "Only scanned players can leave or be removed");
  }
  if (player.device_id === room.owner_device_id) {
    throw httpError(400, "The room owner cannot be removed");
  }

  const isSelf = player.device_id === attachment.deviceId;
  const isOwnerRemoving = room.owner_device_id === attachment.deviceId;
  if (!isSelf && !isOwnerRemoving) {
    throw httpError(403, "You can only leave yourself");
  }

  const update = database.transaction(() => {
    database
      .prepare("UPDATE mahjong_players SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
      .run(player.id);
    database.prepare("DELETE FROM mahjong_room_members WHERE room_id = ? AND device_id = ?").run(attachment.roomId, player.device_id);
    database.prepare("UPDATE mahjong_rooms SET updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(attachment.roomId);
  });
  update();
}

function tableScore(
  database: Database.Database,
  attachment: SocketAttachment,
  message: { amount?: number },
): void {
  const amount = normalizeScoreAmount(message.amount, "amount");
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(attachment.roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }
  if (room.status !== "active") {
    throw httpError(400, "Room is not active");
  }

  const actingPlayer = database
    .prepare("SELECT * FROM mahjong_players WHERE room_id = ? AND device_id = ? AND is_active = 1")
    .get(attachment.roomId, attachment.deviceId) as PlayerRow | undefined;
  if (!actingPlayer) {
    throw httpError(404, "Player not found");
  }

  const update = database.transaction(() => {
    let tablePlayer = database
      .prepare("SELECT * FROM mahjong_players WHERE room_id = ? AND name = '台板' AND is_active = 1")
      .get(attachment.roomId) as PlayerRow | undefined;

    if (!tablePlayer) {
      const count = (database.prepare("SELECT COUNT(*) AS count FROM mahjong_players WHERE room_id = ?").get(attachment.roomId) as { count: number }).count;
      const tablePlayerId = crypto.randomUUID();
      database
        .prepare(
          `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
           VALUES (?, ?, '台板', NULL, 'table', 0, ?)`,
        )
        .run(tablePlayerId, attachment.roomId, count);
      tablePlayer = database.prepare("SELECT * FROM mahjong_players WHERE id = ?").get(tablePlayerId) as PlayerRow;
    }

    database
      .prepare("UPDATE mahjong_players SET score = score - ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
      .run(amount, actingPlayer.id);
    const actingUpdated = database.prepare("SELECT score FROM mahjong_players WHERE id = ?").get(actingPlayer.id) as { score: number };
    database
      .prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(crypto.randomUUID(), attachment.roomId, actingPlayer.id, attachment.memberId, -amount, "台板(茶水)", actingUpdated.score);

    database
      .prepare("UPDATE mahjong_players SET score = score + ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
      .run(amount, tablePlayer.id);
    const tableUpdated = database.prepare("SELECT score FROM mahjong_players WHERE id = ?").get(tablePlayer.id) as { score: number };
    database
      .prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(crypto.randomUUID(), attachment.roomId, tablePlayer.id, attachment.memberId, amount, "台板(茶水)", tableUpdated.score);
    database.prepare("UPDATE mahjong_rooms SET updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(attachment.roomId);
  });
  update();
}

function giveScore(
  database: Database.Database,
  attachment: SocketAttachment,
  message: { targetPlayerId?: string; amount?: number; reason?: string },
): void {
  const targetPlayerId = requireString(message.targetPlayerId, "targetPlayerId");
  const amount = normalizeScoreAmount(message.amount, "amount");
  const reason = optionalString(message.reason) ?? "给分";
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(attachment.roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }
  if (room.status !== "active") {
    throw httpError(400, "Room is not active");
  }

  const actingPlayer = database
    .prepare("SELECT * FROM mahjong_players WHERE room_id = ? AND device_id = ? AND is_active = 1")
    .get(attachment.roomId, attachment.deviceId) as PlayerRow | undefined;
  if (!actingPlayer) {
    throw httpError(404, "Acting player not found");
  }

  const targetPlayer = database
    .prepare("SELECT * FROM mahjong_players WHERE id = ? AND room_id = ? AND is_active = 1")
    .get(targetPlayerId, attachment.roomId) as PlayerRow | undefined;
  if (!targetPlayer) {
    throw httpError(404, "Target player not found");
  }
  if (targetPlayer.id === actingPlayer.id) {
    throw httpError(400, "You cannot give points to yourself");
  }

  const update = database.transaction(() => {
    database
      .prepare("UPDATE mahjong_players SET score = score - ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
      .run(amount, actingPlayer.id);
    const actingUpdated = database.prepare("SELECT score FROM mahjong_players WHERE id = ?").get(actingPlayer.id) as { score: number };
    database
      .prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(crypto.randomUUID(), attachment.roomId, actingPlayer.id, attachment.memberId, -amount, reason, actingUpdated.score);

    database
      .prepare("UPDATE mahjong_players SET score = score + ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
      .run(amount, targetPlayer.id);
    const targetUpdated = database.prepare("SELECT score FROM mahjong_players WHERE id = ?").get(targetPlayer.id) as { score: number };
    database
      .prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(crypto.randomUUID(), attachment.roomId, targetPlayer.id, attachment.memberId, amount, reason, targetUpdated.score);
    database.prepare("UPDATE mahjong_rooms SET updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(attachment.roomId);
  });
  update();
}

function addPlayer(
  database: Database.Database,
  attachment: SocketAttachment,
  message: { name?: string },
): void {
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(attachment.roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }
  if (room.owner_device_id !== attachment.deviceId) {
    throw httpError(403, "Only the room owner can add players");
  }
  const count = (database.prepare("SELECT COUNT(*) AS count FROM mahjong_players WHERE room_id = ?").get(attachment.roomId) as { count: number }).count;
  if (count >= MAX_PLAYERS) {
    throw httpError(400, "Room is full");
  }
  const name = optionalString(message.name) ?? `玩家 ${count + 1}`;
  database
    .prepare(
      `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
       VALUES (?, ?, ?, NULL, NULL, ?, ?)`,
    )
    .run(crypto.randomUUID(), attachment.roomId, name, room.starting_score, count);
  database.prepare("UPDATE mahjong_rooms SET updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(attachment.roomId);
}

function transferOwner(
  database: Database.Database,
  attachment: SocketAttachment,
  message: { targetDeviceId?: string },
): void {
  const targetDeviceId = requireString(message.targetDeviceId, "targetDeviceId");
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(attachment.roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }
  if (room.owner_device_id !== attachment.deviceId) {
    throw httpError(403, "Only the room owner can transfer ownership");
  }
  const targetMember = database
    .prepare("SELECT * FROM mahjong_room_members WHERE room_id = ? AND device_id = ?")
    .get(attachment.roomId, targetDeviceId) as MemberRow | undefined;
  if (!targetMember) {
    throw httpError(404, "Target member not found");
  }

  const update = database.transaction(() => {
    database.prepare("UPDATE mahjong_rooms SET owner_device_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(targetDeviceId, attachment.roomId);
    database.prepare("UPDATE mahjong_room_members SET role = 'player' WHERE room_id = ?").run(attachment.roomId);
    database.prepare("UPDATE mahjong_room_members SET role = 'owner' WHERE id = ?").run(targetMember.id);
  });
  update();
}

function settleRoom(database: Database.Database, roomId: string, multiplier: number): void {
  const players = database.prepare("SELECT * FROM mahjong_players WHERE room_id = ? AND is_active = 1").all(roomId) as PlayerRow[];
  const maxScore = Math.max(...players.map((player) => player.score));
  const minScore = Math.min(...players.map((player) => player.score));
  const update = database.transaction(() => {
    for (const player of players) {
      const result = player.score === maxScore && maxScore !== minScore ? "win" : player.score === minScore && maxScore !== minScore ? "lose" : "draw";
      database
        .prepare("UPDATE mahjong_players SET multiplier_score = ?, result = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
        .run(player.score * multiplier, result, player.id);
    }
    database
      .prepare("UPDATE mahjong_rooms SET status = 'ended', multiplier = ?, ended_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
      .run(multiplier, roomId);
  });
  update();
}

function createJoinedPlayer(
  database: Database.Database,
  roomId: string,
  deviceId: string,
  displayName: string,
  startingScore: number,
): void {
  const count = (database.prepare("SELECT COUNT(*) AS count FROM mahjong_players WHERE room_id = ?").get(roomId) as { count: number }).count;
  const name = optionalString(displayName) ?? `玩家${count + 1}`;
  database
    .prepare(
      `INSERT INTO mahjong_players (id, room_id, name, device_id, seat, score, sort_order)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(crypto.randomUUID(), roomId, name.startsWith("Player") ? `玩家${count + 1}` : name, deviceId, null, startingScore, count);
}

function readBearerToken(request: Request): string | null {
  const header = request.header("authorization");
  if (!header?.toLowerCase().startsWith("bearer ")) {
    return null;
  }

  return header.slice("bearer ".length).trim();
}

function roomInfo(room: RoomRow) {
  return {
    id: room.id,
    code: room.code,
    title: room.title,
    status: room.status,
    mode: room.mode,
    startingScore: room.starting_score,
    ownerDeviceId: room.owner_device_id,
    multiplier: room.multiplier,
    createdAt: room.created_at,
    endedAt: room.ended_at,
    updatedAt: room.updated_at,
  };
}

function adjustScore(
  database: Database.Database,
  attachment: SocketAttachment,
  message: { playerId?: string; delta?: number; reason?: string },
): void {
  const playerId = requireString(message.playerId, "playerId");
  if (!Number.isInteger(message.delta) || message.delta === 0) {
    throw httpError(400, "delta must be a non-zero integer");
  }

  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(attachment.roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }
  if (room.mode === "multiplayer") {
    throw httpError(400, "Use give_score in multiplayer rooms");
  }
  const player = database
    .prepare("SELECT * FROM mahjong_players WHERE id = ? AND room_id = ? AND is_active = 1")
    .get(playerId, attachment.roomId) as PlayerRow | undefined;
  if (!player) {
    throw httpError(404, "Player not found");
  }
  if (room.mode === "solo" && room.owner_device_id !== attachment.deviceId) {
    throw httpError(403, "Only the room owner can score in solo mode");
  }
  const eventId = crypto.randomUUID();
  const reason = optionalString(message.reason) ?? null;

  const update = database.transaction(() => {
    database
      .prepare(
        `UPDATE mahjong_players
         SET score = score + ?, updated_at = CURRENT_TIMESTAMP
         WHERE id = ? AND room_id = ? AND is_active = 1`,
      )
      .run(message.delta, playerId, attachment.roomId);
    const updated = database.prepare("SELECT score FROM mahjong_players WHERE id = ?").get(playerId) as { score: number };
    database
      .prepare(
        `INSERT INTO mahjong_score_events (id, room_id, player_id, actor_member_id, delta, reason, score_after)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(eventId, attachment.roomId, playerId, attachment.memberId, message.delta, reason, updated.score);
    database.prepare("UPDATE mahjong_rooms SET updated_at = CURRENT_TIMESTAMP WHERE id = ?").run(attachment.roomId);
  });
  update();
}

function broadcast(socketsByRoom: Map<string, Set<WebSocket>>, roomId: string, message: unknown): void {
  const serialized = JSON.stringify(message);
  for (const socket of socketsByRoom.get(roomId) ?? []) {
    if (socket.readyState === socket.OPEN) {
      socket.send(serialized);
    }
  }
}

function createUniqueRoomCode(database: Database.Database): string {
  for (let index = 0; index < 16; index += 1) {
    const code = createRoomCode();
    const existing = database.prepare("SELECT id FROM mahjong_rooms WHERE code = ?").get(code);
    if (!existing) {
      return code;
    }
  }

  throw new Error("Failed to allocate room code");
}

function getRoomByCode(database: Database.Database, rawCode: string): RoomRow {
  const code = normalizeRoomCode(rawCode);
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE code = ?").get(code) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }

  return room;
}

function getSnapshot(database: Database.Database, roomId: string) {
  const room = database.prepare("SELECT * FROM mahjong_rooms WHERE id = ?").get(roomId) as RoomRow | undefined;
  if (!room) {
    throw httpError(404, "Room not found");
  }

  const players = database
    .prepare("SELECT * FROM mahjong_players WHERE room_id = ? AND is_active = 1 ORDER BY sort_order ASC")
    .all(roomId) as PlayerRow[];
  const events = database
    .prepare("SELECT * FROM mahjong_score_events WHERE room_id = ? ORDER BY created_at DESC LIMIT 50")
    .all(roomId) as ScoreEventRow[];

  return {
    room: roomInfo(room),
    players: players.map((player) => ({
      id: player.id,
      name: player.name,
      deviceId: player.device_id,
      seat: player.seat,
      score: player.score,
      multiplierScore: player.multiplier_score,
      result: player.result,
      sortOrder: player.sort_order,
      isActive: player.is_active === 1,
    })),
    recentEvents: events.map((event) => ({
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

function normalizePlayers(players: CreateRoomBody["players"], startingScore: number, roomId: string) {
  const rawPlayers: Array<{ name?: string; seat?: string }> =
    Array.isArray(players) && players.length > 0 ? players.slice(0, MAX_PLAYERS) : [{ name: "玩家1", seat: DEFAULT_SEATS[0] }];

  return rawPlayers.map((player, index) => ({
    id: crypto.randomUUID(),
    roomId,
    name: optionalString(player.name) ?? `玩家${index + 1}`,
    seat: optionalString(player.seat) ?? DEFAULT_SEATS[index] ?? null,
    score: startingScore,
    sortOrder: index,
  }));
}

function normalizeStartingScore(value: unknown): number {
  if (value === undefined) {
    return 0;
  }

  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 1000000) {
    throw httpError(400, "startingScore must be an integer between 0 and 1000000");
  }

  return value;
}

function normalizeMode(value: unknown): "multiplayer" | "solo" {
  if (value === undefined) {
    return "multiplayer";
  }

  if (value !== "multiplayer" && value !== "solo") {
    throw httpError(400, "mode must be multiplayer or solo");
  }

  return value;
}

function normalizeMultiplier(value: unknown): number {
  if (value === undefined) {
    return 1;
  }

  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > 1000000) {
    throw httpError(400, "multiplier must be a positive number");
  }

  return value;
}

function normalizeScoreAmount(value: unknown, fieldName: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0 || value > 1000000) {
    throw httpError(400, `${fieldName} must be a positive integer`);
  }

  return value;
}

function normalizeRoomCode(code: string): string {
  const normalized = code.trim().toUpperCase();
  if (!/^[A-Z2-9]{6}$/.test(normalized)) {
    throw httpError(400, "Invalid room code");
  }

  return normalized;
}

function requireString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw httpError(400, `${fieldName} is required`);
  }

  return value.trim();
}

function optionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function createToken(secret: string, roomId: string, memberId: string, deviceId: string): string {
  return createMemberToken(secret, {
    roomId,
    memberId,
    deviceId,
    exp: Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS,
  });
}
