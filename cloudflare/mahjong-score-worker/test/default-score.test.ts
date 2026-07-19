import { describe, expect, it } from "vitest";
import { MahjongRoomObject } from "../src/MahjongRoomObject";

describe("MahjongRoomObject defaults", () => {
  it("uses 0 as the default starting score", () => {
    const roomObject = Object.create(MahjongRoomObject.prototype) as {
      normalizeStartingScore(value: unknown): number;
    };

    expect(roomObject.normalizeStartingScore(undefined)).toBe(0);
  });
});
