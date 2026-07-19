import { emptyCorsResponse, errorResponse, jsonResponse, readJson, requireString } from "./http";
import { createRoomCode, normalizeRoomCode } from "./room-code";
import type { Env, RoomRow } from "./types";
export { MahjongRoomObject } from "./MahjongRoomObject";

interface CreateRoomRequest {
  title?: string;
  mode?: "multiplayer" | "solo";
  startingScore?: number;
  deviceId?: string;
  displayName?: string;
  players?: Array<{ name?: string; seat?: string }>;
}

interface JoinRoomRequest {
  deviceId?: string;
  displayName?: string;
}

interface SettleRoomRequest {
  multiplier?: number;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return emptyCorsResponse();
    }

    try {
      return await route(request, env);
    } catch (error) {
      return errorResponse(error);
    }
  },
};

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const pathParts = url.pathname.split("/").filter(Boolean);

  if (request.method === "GET" && url.pathname === "/health") {
    return jsonResponse({ ok: true });
  }

  if (request.method === "POST" && url.pathname === "/rooms") {
    return createRoom(request, env);
  }

  if (request.method === "GET" && url.pathname === "/history") {
    return getHistory(request, env);
  }

  if (pathParts[0] === "rooms" && pathParts[1]) {
    const code = normalizeRoomCode(pathParts[1]);

    if (request.method === "POST" && pathParts[2] === "join") {
      return forwardToRoom(env, code, "/join", await readJson<JoinRoomRequest>(request), "POST", request.headers);
    }

    if (request.method === "GET" && pathParts.length === 2) {
      return forwardToRoom(env, code, "/snapshot", undefined, "GET");
    }

    if (request.method === "POST" && pathParts[2] === "end") {
      return forwardToRoom(env, code, "/end", undefined, "POST", request.headers);
    }

    if (request.method === "POST" && pathParts[2] === "settle") {
      return forwardToRoom(env, code, "/settle", await readJson<SettleRoomRequest>(request), "POST", request.headers);
    }

    if (request.method === "GET" && pathParts[2] === "ws") {
      return forwardWebSocket(env, code, request);
    }
  }

  return jsonResponse({ error: "Not found" }, { status: 404 });
}

async function createRoom(request: Request, env: Env): Promise<Response> {
  const body = await readJson<CreateRoomRequest>(request);
  const code = await createUniqueRoomCode(env);

  return forwardToRoom(env, code, "/create", {
    ...body,
    code,
  });
}

async function createUniqueRoomCode(env: Env): Promise<string> {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = createRoomCode();
    const existing = await env.DB.prepare("SELECT id FROM mahjong_rooms WHERE code = ?").bind(code).first<{ id: string }>();

    if (!existing) {
      return code;
    }
  }

  throw new Error("Failed to allocate room code");
}

async function getHistory(request: Request, env: Env): Promise<Response> {
  const deviceId = requireString(new URL(request.url).searchParams.get("deviceId"), "deviceId");
  const rows = await env.DB.prepare(
    `SELECT rooms.*
     FROM mahjong_rooms rooms
     INNER JOIN mahjong_room_members members ON members.room_id = rooms.id
     WHERE members.device_id = ? AND members.is_active = 1
     ORDER BY rooms.updated_at DESC
     LIMIT 50`,
  )
    .bind(deviceId)
    .all<RoomRow>();

  return jsonResponse({
    rooms: rows.results.map((room) => ({
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
    })),
  });
}

function forwardToRoom(
  env: Env,
  code: string,
  path: string,
  body?: unknown,
  method = "POST",
  headers?: Headers,
): Promise<Response> {
  const id = env.MAHJONG_ROOM.idFromName(code);
  const stub = env.MAHJONG_ROOM.get(id);
  const request = new Request(`https://mahjong-room.internal${path}?code=${encodeURIComponent(code)}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(headers?.get("authorization") ? { authorization: headers.get("authorization") ?? "" } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  return stub.fetch(request);
}

function forwardWebSocket(env: Env, code: string, request: Request): Promise<Response> {
  const id = env.MAHJONG_ROOM.idFromName(code);
  const stub = env.MAHJONG_ROOM.get(id);
  const url = new URL(request.url);
  const internalUrl = new URL("https://mahjong-room.internal/ws");
  internalUrl.searchParams.set("code", code);

  if (url.searchParams.has("memberToken")) {
    internalUrl.searchParams.set("memberToken", url.searchParams.get("memberToken") ?? "");
  }

  return stub.fetch(new Request(internalUrl, request));
}
