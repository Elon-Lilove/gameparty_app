import { describe, expect, it } from "vitest";
import { MahjongRoomObject } from "../src/MahjongRoomObject";

describe("MahjongRoomObject player limits", () => {
  it("keeps up to twenty players when creating a room", () => {
    const roomObject = Object.create(MahjongRoomObject.prototype) as {
      normalizePlayers(players: Array<{ name: string }>, startingScore: number, roomId: string): Array<{ name: string }>;
    };

    const players = roomObject.normalizePlayers(
      Array.from({ length: 25 }, (_, index) => ({ name: `Player ${index + 1}` })),
      0,
      "room-1",
    );

    expect(players).toHaveLength(20);
    expect(players.at(0)?.name).toBe("Player 1");
    expect(players.at(-1)?.name).toBe("Player 20");
  });

  it("binds a scanned device to its joined player", () => {
    const roomObject = Object.create(MahjongRoomObject.prototype) as {
      normalizeJoinedPlayer(
        roomId: string,
        deviceId: string,
        displayName: string,
        startingScore: number,
        sortOrder: number,
      ): { room_id: string; device_id?: string | null; name: string; score: number; sort_order: number; is_active: number };
    };

    const player = roomObject.normalizeJoinedPlayer("room-1", "device-guest", "Player", 0, 4);

    expect(player.room_id).toBe("room-1");
    expect(player.device_id).toBe("device-guest");
    expect(player.name).toBe("玩家5");
    expect(player.score).toBe(0);
    expect(player.sort_order).toBe(4);
    expect(player.is_active).toBe(1);
  });
});
