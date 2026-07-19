import { afterEach, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { createMahjongSyncServer, type MahjongSyncServer } from "../src/server";

const servers: MahjongSyncServer[] = [];

afterEach(async () => {
  await Promise.all(servers.splice(0).map((server) => server.close()));
});

describe("Mahjong sync server", () => {
  it("creates and joins online rooms", async () => {
    const server = await startServer();
    const created = await createRoom(server.url, { mode: "multiplayer" });
    const joined = await joinRoom(server.url, created.snapshot.room.code, { deviceId: "device-guest" });

    expect(created.snapshot.room.code).toMatch(/^[A-Z2-9]{6}$/);
    expect(created.snapshot.room.mode).toBe("multiplayer");
    expect(created.snapshot.room.ownerDeviceId).toBe("device-owner");
    expect(created.snapshot.players).toEqual([
      expect.objectContaining({ name: "玩家1", deviceId: "device-owner" }),
    ]);
    expect(created.memberToken).toContain(".");
    expect(joined.snapshot.room.code).toBe(created.snapshot.room.code);
    expect(joined.snapshot.players.some((player) => player.name === "玩家2")).toBe(true);
    expect(joined.memberToken).toContain(".");
  });

  it("broadcasts newly scanned players to existing room members immediately", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const owner = await connectSocket(server.url, created.snapshot.room.code, created.memberToken);
    await owner.nextState();

    await joinRoom(server.url, created.snapshot.room.code, { deviceId: "device-guest" });
    const update = await owner.nextState();

    expect(update.snapshot.players).toHaveLength(2);
    expect(update.snapshot.players[1]).toEqual(expect.objectContaining({ name: "玩家2", deviceId: "device-guest" }));
    owner.socket.close();
  });

  it("lists unfinished rooms for a device", async () => {
    const server = await startServer();
    const created = await createRoom(server.url, { mode: "solo" });
    const response = await fetch(`${server.url}/history?deviceId=device-owner`);
    const body = (await response.json()) as { rooms: Array<{ code: string; mode: string; status: string }> };

    expect(response.status).toBe(200);
    expect(body.rooms).toEqual([
      expect.objectContaining({
        code: created.snapshot.room.code,
        mode: "solo",
        status: "active",
      }),
    ]);
  });

  it("moves points from the acting player to the target player", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const joined = await joinRoom(server.url, created.snapshot.room.code);
    const ownerPlayerId = created.snapshot.players[0].id;
    const guestPlayerId = joined.snapshot.players.find((player) => player.deviceId === "device-guest")?.id;
    expect(guestPlayerId).toBeTruthy();

    const owner = await connectSocket(server.url, created.snapshot.room.code, created.memberToken);
    const guest = await connectSocket(server.url, created.snapshot.room.code, joined.memberToken);
    await owner.nextState();
    await guest.nextState();

    owner.socket.send(JSON.stringify({ type: "give_score", targetPlayerId: guestPlayerId, amount: 5 }));
    const update = await guest.nextState();

    expect(update.snapshot.players.find((player) => player.id === ownerPlayerId)?.score).toBe(-5);
    expect(update.snapshot.players.find((player) => player.id === guestPlayerId)?.score).toBe(5);

    owner.socket.close();
    guest.socket.close();
  });

  it("rejects direct score adjustment in multiplayer rooms", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const playerId = created.snapshot.players[0].id;
    const owner = await connectSocket(server.url, created.snapshot.room.code, created.memberToken);
    await owner.nextState();

    owner.socket.send(JSON.stringify({ type: "adjust_score", playerId, delta: 5 }));
    const error = await owner.nextError();

    expect(error.error).toBe("Use give_score in multiplayer rooms");
    owner.socket.close();
  });

  it("renames a player's own display name", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const joined = await joinRoom(server.url, created.snapshot.room.code, { deviceId: "device-guest" });
    const player = joined.snapshot.players.find((candidate) => candidate.deviceId === "device-guest");
    expect(player).toBeTruthy();

    const guest = await connectSocket(server.url, created.snapshot.room.code, joined.memberToken);
    await guest.nextState();
    guest.socket.send(JSON.stringify({ type: "rename_player", playerId: player!.id, name: "阿龙" }));
    const update = await guest.nextState();

    expect(update.snapshot.players.find((candidate) => candidate.id === player!.id)?.name).toBe("阿龙");
    guest.socket.close();
  });

  it("transfers ownership to a scanned player", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const joined = await joinRoom(server.url, created.snapshot.room.code, { deviceId: "device-guest" });
    const owner = await connectSocket(server.url, created.snapshot.room.code, created.memberToken);
    await owner.nextState();

    owner.socket.send(JSON.stringify({ type: "transfer_owner", targetDeviceId: "device-guest" }));
    const update = await owner.nextState();

    expect(update.snapshot.room.ownerDeviceId).toBe("device-guest");
    expect(joined.snapshot.players.some((player) => player.deviceId === "device-guest")).toBe(true);
    owner.socket.close();
  });

  it("lets the owner remove a scanned player", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const joined = await joinRoom(server.url, created.snapshot.room.code, { deviceId: "device-guest" });
    const guestPlayer = joined.snapshot.players.find((player) => player.deviceId === "device-guest");
    expect(guestPlayer).toBeTruthy();

    const owner = await connectSocket(server.url, created.snapshot.room.code, created.memberToken);
    await owner.nextState();
    owner.socket.send(JSON.stringify({ type: "remove_player", playerId: guestPlayer!.id }));
    const update = await owner.nextState();

    expect(update.snapshot.players.some((player) => player.id === guestPlayer!.id)).toBe(false);
    owner.socket.close();
  });

  it("lets a player leave their room", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const joined = await joinRoom(server.url, created.snapshot.room.code, { deviceId: "device-guest" });
    const guestPlayer = joined.snapshot.players.find((player) => player.deviceId === "device-guest");
    expect(guestPlayer).toBeTruthy();

    const guest = await connectSocket(server.url, created.snapshot.room.code, joined.memberToken);
    await guest.nextState();
    guest.socket.send(JSON.stringify({ type: "remove_player", playerId: guestPlayer!.id }));
    const update = await guest.nextState();

    expect(update.snapshot.players.some((player) => player.id === guestPlayer!.id)).toBe(false);
    guest.socket.close();
  });

  it("moves tea-table points from the acting player to the table", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const ownerPlayerId = created.snapshot.players[0].id;
    const owner = await connectSocket(server.url, created.snapshot.room.code, created.memberToken);
    await owner.nextState();

    owner.socket.send(JSON.stringify({ type: "table_score", amount: 3 }));
    const update = await owner.nextState();
    const ownerPlayer = update.snapshot.players.find((player) => player.id === ownerPlayerId);
    const tablePlayer = update.snapshot.players.find((player) => player.name === "台板");

    expect(ownerPlayer?.score).toBe(-3);
    expect(tablePlayer?.score).toBe(3);
    owner.socket.close();
  });

  it("settles a room with multiplier details", async () => {
    const server = await startServer();
    const created = await createRoom(server.url);
    const joined = await joinRoom(server.url, created.snapshot.room.code, { deviceId: "device-guest" });
    const room = await fetch(`${server.url}/rooms/${created.snapshot.room.code}`);
    const snapshot = (await room.json()) as RoomSnapshot;
    const playerId = created.snapshot.players[0].id;
    const owner = await connectSocket(server.url, created.snapshot.room.code, created.memberToken);
    const guest = await connectSocket(server.url, created.snapshot.room.code, joined.memberToken);
    await owner.nextState();
    await guest.nextState();
    guest.socket.send(JSON.stringify({ type: "give_score", targetPlayerId: playerId, amount: 8 }));
    await owner.nextState();

    const response = await fetch(`${server.url}/rooms/${created.snapshot.room.code}/settle`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${created.memberToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ multiplier: 2 }),
    });
    const body = (await response.json()) as { snapshot: RoomSnapshot };

    expect(response.status).toBe(200);
    expect(body.snapshot.room.status).toBe("ended");
    expect(body.snapshot.room.multiplier).toBe(2);
    expect(body.snapshot.players[0].multiplierScore).toBe(16);
    expect(body.snapshot.players[0].result).toBe("win");
    expect(snapshot.players).toHaveLength(2);
    owner.socket.close();
    guest.socket.close();
  });
});

async function startServer() {
  const server = await createMahjongSyncServer({
    databasePath: ":memory:",
    memberTokenSecret: "test-secret",
    port: 0,
  });
  servers.push(server);
  return server;
}

async function createRoom(baseURL: string, options: { mode?: "multiplayer" | "solo" } = {}) {
  const response = await fetch(`${baseURL}/rooms`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      deviceId: "device-owner",
      displayName: "Owner",
      title: "Friday Mahjong",
      mode: options.mode ?? "multiplayer",
      startingScore: 0,
      players: [{ name: "玩家1" }],
    }),
  });

  expect(response.status).toBe(200);
  return response.json() as Promise<RoomResponse>;
}

async function joinRoom(baseURL: string, code: string, options: { deviceId?: string; displayName?: string } = {}) {
  const response = await fetch(`${baseURL}/rooms/${code}/join`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ deviceId: options.deviceId ?? "device-guest", displayName: options.displayName }),
  });

  expect(response.status).toBe(200);
  return response.json() as Promise<RoomResponse>;
}

function connectSocket(baseURL: string, code: string, memberToken: string) {
  const url = `${baseURL.replace(/^http/, "ws")}/rooms/${code}/ws?memberToken=${encodeURIComponent(memberToken)}`;
  const socket = new WebSocket(url);
  const messages: Array<(message: StateMessage) => void> = [];
  const errors: Array<(message: ErrorMessage) => void> = [];
  const queued: StateMessage[] = [];
  const queuedErrors: ErrorMessage[] = [];

  socket.on("message", (raw) => {
    const message = JSON.parse(String(raw)) as StateMessage | ErrorMessage;
    if (message.type === "error") {
      const resolveError = errors.shift();
      if (resolveError) {
        resolveError(message);
      } else {
        queuedErrors.push(message);
      }
      return;
    }

    const resolve = messages.shift();
    if (resolve) {
      resolve(message);
    } else {
      queued.push(message);
    }
  });

  return new Promise<{ socket: WebSocket; nextState: () => Promise<StateMessage>; nextError: () => Promise<ErrorMessage> }>((resolve, reject) => {
    socket.on("error", reject);
    socket.on("open", () => {
      resolve({
        socket,
        nextState: () => {
          const queuedMessage = queued.shift();
          if (queuedMessage) {
            return Promise.resolve(queuedMessage);
          }

          return new Promise<StateMessage>((messageResolve) => {
            messages.push(messageResolve);
          });
        },
        nextError: () => {
          const queuedError = queuedErrors.shift();
          if (queuedError) {
            return Promise.resolve(queuedError);
          }

          return new Promise<ErrorMessage>((messageResolve) => {
            errors.push(messageResolve);
          });
        },
      });
    });
  });
}

interface RoomResponse {
  memberToken: string;
  snapshot: RoomSnapshot;
}

interface RoomSnapshot {
  room: { code: string; mode: string; status: string; ownerDeviceId: string; multiplier?: number };
  players: Array<{ id: string; name: string; deviceId?: string; score: number; multiplierScore?: number; result?: string }>;
}

interface StateMessage {
  type: "state";
  snapshot: RoomSnapshot;
}

interface ErrorMessage {
  type: "error";
  error: string;
}
