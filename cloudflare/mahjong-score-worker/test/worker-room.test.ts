import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

interface RoomResponse {
  memberToken: string;
  snapshot: {
    room: { code: string; multiplier: number; ownerDeviceId: string; status: string };
    players: Array<{
      deviceId: string | null;
      id: string;
      isActive: boolean;
      multiplierScore: number;
      name: string;
      result: string | null;
      score: number;
    }>;
  };
}

interface SocketEnvelope {
  type: string;
  error?: string;
  operationId?: string;
  actorDeviceId?: string;
  snapshot?: {
    room: { ownerDeviceId: string };
    players: Array<{
      deviceId: string | null;
      id: string;
      isActive: boolean;
      multiplierScore: number;
      name: string;
      result: string | null;
      score: number;
    }>;
    recentEvents: Array<{ delta: number }>;
  };
}

async function createRoom(overrides: Record<string, unknown> = {}): Promise<RoomResponse> {
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
  return response.json() as Promise<RoomResponse>;
}

async function joinRoom(code: string, deviceId: string, displayName: string, memberToken?: string) {
  const response = await SELF.fetch(`https://worker.test/rooms/${code}/join`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(memberToken ? { authorization: `Bearer ${memberToken}` } : {}),
    },
    body: JSON.stringify({ deviceId, displayName }),
  });

  return { response, body: (await response.json()) as RoomResponse };
}

function nextSocketMessage(socket: WebSocket): Promise<SocketEnvelope> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Timed out waiting for websocket message")), 1_000);
    socket.addEventListener(
      "message",
      (event) => {
        clearTimeout(timeout);
        resolve(JSON.parse(String(event.data)) as SocketEnvelope);
      },
      { once: true },
    );
  });
}

async function connectRoom(code: string, memberToken: string) {
  const response = await SELF.fetch(
    `https://worker.test/rooms/${code}/ws?memberToken=${encodeURIComponent(memberToken)}`,
    { headers: { upgrade: "websocket" } },
  );
  const socket = response.webSocket;

  if (!socket) {
    throw new Error(`WebSocket upgrade failed with status ${response.status}`);
  }

  socket.accept();
  await nextSocketMessage(socket);
  return { socket, next: () => nextSocketMessage(socket) };
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
    const second = await joinRoom(created.snapshot.room.code, "guest-device", "小雨", first.body.memberToken);

    expect(first.response.status).toBe(200);
    expect(second.body.snapshot.players.filter((player) => player.deviceId === "guest-device")).toHaveLength(1);
    expect(second.body.snapshot.players).toContainEqual(expect.objectContaining({ name: "小雨" }));
  });

  it("requires the existing member token when a device id is reused", async () => {
    const created = await createRoom();

    const impersonation = await joinRoom(created.snapshot.room.code, "owner-device", "冒充房主");
    expect(impersonation.response.status).toBe(401);

    const resumed = await joinRoom(created.snapshot.room.code, "owner-device", "阿龙", created.memberToken);
    expect(resumed.response.status).toBe(200);
    expect(resumed.body.snapshot.players.filter((player) => player.deviceId === "owner-device")).toHaveLength(1);
  });

  it("transfers give-score points as a zero-sum operation", async () => {
    const created = await createRoom();
    const joined = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const guest = joined.body.snapshot.players.find((player) => player.deviceId === "guest-device");
    const owner = await connectRoom(created.snapshot.room.code, created.memberToken);

    expect(guest).toBeDefined();
    owner.socket.send(
      JSON.stringify({ type: "give_score", targetPlayerId: guest?.id, amount: 13, operationId: "give-13" }),
    );

    const message = await owner.next();
    const players = message.snapshot?.players ?? [];

    expect(message.type).toBe("state");
    expect(message.operationId).toBe("give-13");
    expect(message.actorDeviceId).toBe("owner-device");
    expect(players.find((player) => player.deviceId === "owner-device")?.score).toBe(-13);
    expect(players.find((player) => player.id === guest?.id)?.score).toBe(13);
    expect(message.snapshot?.recentEvents.filter((event) => Math.abs(event.delta) === 13)).toHaveLength(2);
    owner.socket.close();
  });

  it("records a table-board charge against the active player", async () => {
    const created = await createRoom();
    const owner = await connectRoom(created.snapshot.room.code, created.memberToken);

    owner.socket.send(JSON.stringify({ type: "table_score", amount: 7 }));

    const message = await owner.next();
    const players = message.snapshot?.players ?? [];

    expect(message.type).toBe("state");
    expect(players.find((player) => player.deviceId === "owner-device")?.score).toBe(-7);
    expect(players).toContainEqual(expect.objectContaining({ name: "台板", score: 7 }));
    expect(message.snapshot?.recentEvents.filter((event) => Math.abs(event.delta) === 7)).toHaveLength(2);
    owner.socket.close();
  });

  it("transfers ownership only to an active scanned member", async () => {
    const created = await createRoom();
    const joined = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const owner = await connectRoom(created.snapshot.room.code, created.memberToken);
    const guest = await connectRoom(created.snapshot.room.code, joined.body.memberToken);
    const guestPromotion = guest.next();

    owner.socket.send(JSON.stringify({ type: "transfer_owner", targetDeviceId: "guest-device" }));

    const message = await owner.next();

    expect(message.type).toBe("state");
    expect(message.snapshot?.room.ownerDeviceId).toBe("guest-device");
    expect(joined.body.snapshot.room.ownerDeviceId).toBe("owner-device");
    expect((await guestPromotion).snapshot?.room.ownerDeviceId).toBe("guest-device");

    const ownerPromotion = owner.next();
    guest.socket.send(JSON.stringify({ type: "transfer_owner", targetDeviceId: "owner-device" }));
    const transferredBack = await guest.next();
    expect(transferredBack.snapshot?.room.ownerDeviceId).toBe("owner-device");
    expect((await ownerPromotion).snapshot?.room.ownerDeviceId).toBe("owner-device");

    guest.socket.close();
    owner.socket.close();
  });

  it("lets the owner remove a scanned player and invalidates the old member token", async () => {
    const created = await createRoom();
    const joined = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const guest = joined.body.snapshot.players.find((player) => player.deviceId === "guest-device");
    const owner = await connectRoom(created.snapshot.room.code, created.memberToken);
    const guestConnection = await connectRoom(created.snapshot.room.code, joined.body.memberToken);
    const guestUpdate = guestConnection.next();
    const guestClosed = new Promise<void>((resolve) => guestConnection.socket.addEventListener("close", () => resolve(), { once: true }));

    owner.socket.send(JSON.stringify({ type: "remove_player", playerId: guest?.id }));

    const message = await owner.next();
    expect(message.type).toBe("state");
    expect(message.snapshot?.players.some((player) => player.id === guest?.id)).toBe(false);
    expect((await guestUpdate).snapshot?.players.some((player) => player.id === guest?.id)).toBe(false);
    await guestClosed;

    const reconnect = await SELF.fetch(
      `https://worker.test/rooms/${created.snapshot.room.code}/ws?memberToken=${encodeURIComponent(joined.body.memberToken)}`,
      { headers: { upgrade: "websocket" } },
    );
    expect(reconnect.status).toBe(403);

    const rejoin = await joinRoom(
      created.snapshot.room.code,
      "guest-device",
      "小雨",
      joined.body.memberToken,
    );
    expect(rejoin.response.status).toBe(403);
    guestConnection.socket.close();
    owner.socket.close();
  });

  it("rejects removing a player whose balance is not zero", async () => {
    const created = await createRoom();
    const joined = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const guest = joined.body.snapshot.players.find((player) => player.deviceId === "guest-device");
    const owner = await connectRoom(created.snapshot.room.code, created.memberToken);

    owner.socket.send(JSON.stringify({ type: "give_score", targetPlayerId: guest?.id, amount: 5 }));
    await owner.next();
    owner.socket.send(JSON.stringify({ type: "remove_player", playerId: guest?.id, operationId: "remove-scored" }));
    const rejected = await owner.next();

    expect(rejected.type).toBe("error");
    expect(rejected.error).toMatch(/balance.*zero/i);
    expect(rejected.operationId).toBe("remove-scored");
    owner.socket.close();
  });

  it("requires give-score in multiplayer rooms and protects player names", async () => {
    const created = await createRoom();
    const joined = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const ownerPlayer = created.snapshot.players.find((player) => player.deviceId === "owner-device");
    const guestPlayer = joined.body.snapshot.players.find((player) => player.deviceId === "guest-device");
    const guest = await connectRoom(created.snapshot.room.code, joined.body.memberToken);

    guest.socket.send(
      JSON.stringify({ type: "adjust_score", playerId: ownerPlayer?.id, delta: 5, operationId: "invalid-score" }),
    );
    const rejectedAdjustment = await guest.next();
    expect(rejectedAdjustment.error).toMatch(/Use give_score/);
    expect(rejectedAdjustment.operationId).toBe("invalid-score");
    expect(rejectedAdjustment.actorDeviceId).toBe("guest-device");

    guest.socket.send(JSON.stringify({ type: "rename_player", playerId: ownerPlayer?.id, name: "不应修改" }));
    const rejectedRename = await guest.next();
    expect(rejectedRename.error).toMatch(/only rename yourself/i);

    guest.socket.send(JSON.stringify({ type: "rename_player", playerId: guestPlayer?.id, name: "小雨二号" }));
    const renamed = await guest.next();
    expect(renamed.snapshot?.players.find((player) => player.id === guestPlayer?.id)?.name).toBe("小雨二号");
    guest.socket.close();
  });

  it("allows manual players only for the solo-room owner", async () => {
    const solo = await createRoom({ mode: "solo", players: [{ name: "房主" }] });
    const soloOwner = await connectRoom(solo.snapshot.room.code, solo.memberToken);
    soloOwner.socket.send(JSON.stringify({ type: "add_player", name: "手动玩家" }));
    const soloMessage = await soloOwner.next();
    expect(soloMessage.snapshot?.players).toContainEqual(expect.objectContaining({ name: "手动玩家" }));
    soloOwner.socket.close();

    const multiplayer = await createRoom();
    const multiplayerOwner = await connectRoom(multiplayer.snapshot.room.code, multiplayer.memberToken);
    multiplayerOwner.socket.send(JSON.stringify({ type: "add_player", name: "不应添加" }));
    const multiplayerMessage = await multiplayerOwner.next();
    expect(multiplayerMessage.error).toMatch(/Only solo-room owners/);
    multiplayerOwner.socket.close();
  });

  it("settles an active room with the owner-selected multiplier", async () => {
    const created = await createRoom();
    const joined = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const guest = joined.body.snapshot.players.find((player) => player.deviceId === "guest-device");
    const owner = await connectRoom(created.snapshot.room.code, created.memberToken);
    owner.socket.send(JSON.stringify({ type: "give_score", targetPlayerId: guest?.id, amount: 13 }));
    await owner.next();
    owner.socket.close();

    const nonOwnerEnd = await SELF.fetch(`https://worker.test/rooms/${created.snapshot.room.code}/end`, {
      method: "POST",
      headers: { authorization: `Bearer ${joined.body.memberToken}` },
    });
    expect(nonOwnerEnd.status).toBe(403);

    const invalidMultiplier = await SELF.fetch(`https://worker.test/rooms/${created.snapshot.room.code}/settle`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${created.memberToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ multiplier: 0 }),
    });
    expect(invalidMultiplier.status).toBe(400);

    const response = await SELF.fetch(`https://worker.test/rooms/${created.snapshot.room.code}/settle`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${created.memberToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ multiplier: 2 }),
    });
    const body = (await response.json()) as { snapshot: RoomResponse["snapshot"] };

    expect(response.status).toBe(200);
    expect(body.snapshot.room).toEqual(expect.objectContaining({ status: "ended", multiplier: 2 }));
    expect(body.snapshot.players.find((player) => player.deviceId === "guest-device")).toEqual(
      expect.objectContaining({ result: "win", multiplierScore: 26 }),
    );
    expect(body.snapshot.players.find((player) => player.deviceId === "owner-device")).toEqual(
      expect.objectContaining({ result: "lose", multiplierScore: -26 }),
    );

    const endedJoin = await joinRoom(created.snapshot.room.code, "late-device", "迟到玩家");
    expect(endedJoin.response.status).toBe(409);

    const resumedOwner = await joinRoom(
      created.snapshot.room.code,
      "owner-device",
      "阿龙",
      created.memberToken,
    );
    expect(resumedOwner.response.status).toBe(200);

    const endedOwner = await connectRoom(created.snapshot.room.code, created.memberToken);
    endedOwner.socket.send(JSON.stringify({ type: "give_score", targetPlayerId: guest?.id, amount: 1 }));
    expect((await endedOwner.next()).error).toMatch(/Room is not active/);
    endedOwner.socket.close();
  });

  it("serializes scoring with settlement so multiplier scores stay consistent", async () => {
    const created = await createRoom();
    const joined = await joinRoom(created.snapshot.room.code, "guest-device", "小雨");
    const guest = joined.body.snapshot.players.find((player) => player.deviceId === "guest-device");
    const owner = await connectRoom(created.snapshot.room.code, created.memberToken);

    owner.socket.send(JSON.stringify({ type: "give_score", targetPlayerId: guest?.id, amount: 9, operationId: "race-score" }));
    const settleResponse = await SELF.fetch(`https://worker.test/rooms/${created.snapshot.room.code}/settle`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${created.memberToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ multiplier: 2 }),
    });
    expect(settleResponse.status).toBe(200);

    const finalResponse = await SELF.fetch(`https://worker.test/rooms/${created.snapshot.room.code}`);
    const finalSnapshot = (await finalResponse.json()) as RoomResponse["snapshot"];
    expect(finalSnapshot.room.status).toBe("ended");
    for (const player of finalSnapshot.players) {
      expect(player.multiplierScore).toBe(player.score * 2);
    }
    owner.socket.close();
  });
});
