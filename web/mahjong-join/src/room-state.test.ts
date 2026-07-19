import { describe, expect, it } from "vitest";
import {
  applyEnvelope,
  beginOperation,
  canGiveScore,
  canSendMutation,
  isOwner,
  parseMultiplier,
  parseScoreAmount,
  type RoomClientState,
  type Snapshot,
} from "./room-state";

const snapshot: Snapshot = {
  room: {
    code: "ABC123",
    title: "麻将计分",
    status: "active",
    mode: "multiplayer",
    ownerDeviceId: "owner-device",
    multiplier: 1,
  },
  players: [
    {
      id: "owner-player",
      name: "房主",
      deviceId: "owner-device",
      score: 0,
      multiplierScore: 0,
      sortOrder: 0,
      isActive: true,
    },
    {
      id: "guest-player",
      name: "玩家",
      deviceId: "guest-device",
      score: 0,
      multiplierScore: 0,
      sortOrder: 1,
      isActive: true,
    },
  ],
  recentEvents: [],
};

describe("room action state", () => {
  it("accepts only integer score amounts in range", () => {
    expect(parseScoreAmount("13")).toEqual({ ok: true, value: 13 });
    expect(parseScoreAmount("0").ok).toBe(false);
    expect(parseScoreAmount("1.5").ok).toBe(false);
    expect(parseScoreAmount("1000001").ok).toBe(false);
    expect(parseScoreAmount("abc").ok).toBe(false);
  });

  it("accepts only settlement multipliers inside range", () => {
    expect(parseMultiplier("1.5")).toEqual({ ok: true, value: 1.5 });
    expect(parseMultiplier("0").ok).toBe(false);
    expect(parseMultiplier("1000001").ok).toBe(false);
  });

  it("clears only the matching pending operation", () => {
    const state: RoomClientState = {
      connection: "connected",
      snapshot,
      pending: beginOperation("give_score", "op-1"),
    };

    expect(applyEnvelope(state, { type: "state", operationId: "other", actorDeviceId: "owner-device" }, "owner-device").pending)
      .toEqual(state.pending);
    expect(applyEnvelope(state, { type: "state", operationId: "op-1", actorDeviceId: "owner-device" }, "owner-device").pending)
      .toBeUndefined();
  });

  it("allows mutations only when active, connected, and idle", () => {
    const state: RoomClientState = { connection: "connected", snapshot };
    expect(canSendMutation(state)).toBe(true);
    expect(canSendMutation({ ...state, connection: "reconnecting" })).toBe(false);
    expect(canSendMutation({ ...state, pending: beginOperation("rename_player", "op") })).toBe(false);
    expect(canSendMutation({ ...state, settling: true })).toBe(false);
  });

  it("derives owner and give-score permissions from the snapshot", () => {
    expect(isOwner(snapshot, "owner-device")).toBe(true);
    expect(isOwner(snapshot, "guest-device")).toBe(false);
    expect(canGiveScore(snapshot, "owner-device", "guest-player")).toBe(true);
    expect(canGiveScore(snapshot, "guest-device", "guest-player")).toBe(false);
  });
});
