import { describe, expect, it } from "vitest";
import { createRoomCode, normalizeRoomCode } from "../src/room-code";

describe("room code helpers", () => {
  it("normalizes lowercase and spaced room codes", () => {
    expect(normalizeRoomCode(" ab 12 cd ")).toBe("AB12CD");
  });

  it("rejects invalid room code characters", () => {
    expect(() => normalizeRoomCode("AB-12")).toThrow(/invalid room code/i);
  });

  it("creates six-character shareable room codes", () => {
    const code = createRoomCode(() => 0);

    expect(code).toHaveLength(6);
    expect(code).toMatch(/^[A-Z0-9]+$/);
  });
});
