import { describe, expect, it } from "vitest";
import type { Snapshot } from "./room-state";
import { renderRoomView } from "./room-view";

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
    { id: "owner", name: "阿龙", deviceId: "owner-device", score: 0, multiplierScore: 0, sortOrder: 0, isActive: true },
    { id: "guest", name: "小雨", deviceId: "guest-device", score: 0, multiplierScore: 0, sortOrder: 1, isActive: true },
  ],
  recentEvents: [
    { id: "event", playerId: "guest", delta: 13, reason: "给分", scoreAfter: 13, createdAt: "2026-07-13 20:00:00" },
  ],
};

function toolbarHTML(html: string): string {
  return html.match(/<nav class="room-tools"[\s\S]*?<\/nav>/)?.[0] ?? "";
}

describe("host-aligned room view", () => {
  it("renders the owner toolbar, player table, details, and settlement", () => {
    const html = renderRoomView(snapshot, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: true,
      voiceEnabled: false,
      detailsVisible: true,
    });

    expect(html).toContain("房间号 ABC123");
    const labels = ["玩家邀请", "房主转让", "语音播放", "台板（茶水）"];
    let previousIndex = -1;
    for (const label of labels) {
      const index = html.indexOf(label);
      expect(index).toBeGreaterThan(previousIndex);
      previousIndex = index;
    }
    expect(html.match(/data-tool=/g)).toHaveLength(4);
    expect(html).not.toContain("data-table-score");
    expect(toolbarHTML(html)).not.toContain('data-action="leave"');
    expect(html).toContain("给分详情");
    expect(html).toContain("结算房间");
    expect(html).toContain("阿龙");
    expect(html).toContain("小雨");
    expect(html).toContain('data-remove="guest"');
  });

  it("hides owner-only controls from a guest while retaining shared controls", () => {
    const html = renderRoomView(snapshot, {
      deviceId: "guest-device",
      connection: "connected",
      tableEnabled: false,
      voiceEnabled: true,
      detailsVisible: false,
    });

    expect(html).not.toContain("房主转让");
    expect(html).not.toContain("data-action=\"settle\"");
    expect(html).not.toContain("data-remove=");
    expect(html).toContain('data-action="leave"');
    expect(toolbarHTML(html)).not.toContain('data-action="leave"');
    expect(html).toContain("语音播放");
    expect(html.match(/data-tool=/g)).toHaveLength(3);
    expect(html).toContain("给分详情");
  });

  it("locks every mutation control while settlement is in progress", () => {
    const html = renderRoomView(snapshot, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: true,
      voiceEnabled: false,
      detailsVisible: false,
      settling: true,
    });

    expect(html).not.toContain("data-give=");
    expect(html).not.toContain("data-table-score");
    expect(html).toContain('data-action="settle" disabled');
  });

  it("disables removal and leaving until the player's balance returns to zero", () => {
    const nonzeroSnapshot: Snapshot = {
      ...snapshot,
      players: snapshot.players.map((player) =>
        player.id === "guest" ? { ...player, score: 5 } : player,
      ),
    };

    const ownerHTML = renderRoomView(nonzeroSnapshot, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: false,
      voiceEnabled: false,
      detailsVisible: false,
    });
    const guestHTML = renderRoomView(nonzeroSnapshot, {
      deviceId: "guest-device",
      connection: "connected",
      tableEnabled: false,
      voiceEnabled: false,
      detailsVisible: false,
    });

    expect(ownerHTML).not.toContain('data-remove="guest"');
    expect(guestHTML).toContain('data-action="leave" disabled');
    expect(guestHTML).toContain("分数归零后才能退出房间");
  });

  it("moves ownership controls immediately with the authoritative owner id", () => {
    const transferred: Snapshot = {
      ...snapshot,
      room: { ...snapshot.room, ownerDeviceId: "guest-device" },
    };

    const newOwnerHTML = renderRoomView(transferred, {
      deviceId: "guest-device",
      connection: "connected",
      tableEnabled: false,
      voiceEnabled: false,
      detailsVisible: false,
    });
    const oldOwnerHTML = renderRoomView(transferred, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: false,
      voiceEnabled: false,
      detailsVisible: false,
    });

    expect(newOwnerHTML).toContain('data-action="open-transfer"');
    expect(oldOwnerHTML).not.toContain('data-action="open-transfer"');
  });

  it("does not render owner transfer in a solo room", () => {
    const soloSnapshot: Snapshot = {
      ...snapshot,
      room: { ...snapshot.room, mode: "solo" },
    };
    const html = renderRoomView(soloSnapshot, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: false,
      voiceEnabled: false,
      detailsVisible: false,
    });

    expect(html).not.toContain('data-action="open-transfer"');
    expect(html.match(/data-tool=/g)).toHaveLength(3);
  });

  it("shows one table-row scoring entry only while table service is enabled", () => {
    const enabledHTML = renderRoomView(snapshot, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: true,
      voiceEnabled: false,
      detailsVisible: false,
    });
    const disabledHTML = renderRoomView(snapshot, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: false,
      voiceEnabled: false,
      detailsVisible: false,
    });
    const authoritativeTable: Snapshot = {
      ...snapshot,
      players: [
        ...snapshot.players,
        { id: "table", name: "台板", deviceId: null, seat: "table", score: 4, multiplierScore: 0, sortOrder: 2, isActive: true },
      ],
    };
    const authoritativeHTML = renderRoomView(authoritativeTable, {
      deviceId: "owner-device",
      connection: "connected",
      tableEnabled: true,
      voiceEnabled: false,
      detailsVisible: false,
    });

    expect(enabledHTML.match(/data-table-give/g)).toHaveLength(1);
    expect(enabledHTML).toContain("台板");
    expect(disabledHTML).not.toContain("data-table-give");
    expect(authoritativeHTML.match(/data-table-give/g)).toHaveLength(1);
  });
});
