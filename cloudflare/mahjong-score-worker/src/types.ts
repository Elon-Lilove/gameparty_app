export interface Env {
  DB: D1Database;
  MAHJONG_ROOM: DurableObjectNamespace;
  MEMBER_TOKEN_SECRET: string;
}

export type RoomStatus = "active" | "ended";
export type MemberRole = "owner" | "player";

export interface RoomRow {
  id: string;
  code: string;
  title: string;
  status: RoomStatus;
  mode?: string;
  starting_score: number;
  owner_device_id: string;
  multiplier?: number;
  created_at: string;
  ended_at: string | null;
  updated_at: string;
}

export interface PlayerRow {
  id: string;
  room_id: string;
  name: string;
  device_id?: string | null;
  seat: string | null;
  score: number;
  multiplier_score?: number;
  result?: string | null;
  sort_order: number;
  is_active: number;
  created_at: string;
  updated_at: string;
}

export interface MemberRow {
  id: string;
  room_id: string;
  device_id: string;
  display_name: string;
  role: MemberRole;
  is_active: number;
  joined_at: string;
}

export interface ScoreEventRow {
  id: string;
  room_id: string;
  player_id: string;
  actor_member_id: string;
  delta: number;
  reason: string | null;
  score_after: number;
  created_at: string;
}

export interface RoomSnapshot {
  room: {
    id: string;
    code: string;
    title: string;
    status: RoomStatus;
    mode: string;
    startingScore: number;
    ownerDeviceId: string;
    multiplier: number;
    createdAt: string;
    endedAt: string | null;
    updatedAt: string;
  };
  players: Array<{
    id: string;
    name: string;
    deviceId?: string | null;
    seat: string | null;
    score: number;
    multiplierScore: number;
    result: string | null;
    sortOrder: number;
    isActive: boolean;
  }>;
  recentEvents: Array<{
    id: string;
    playerId: string;
    actorMemberId: string;
    delta: number;
    reason: string | null;
    scoreAfter: number;
    createdAt: string;
  }>;
}

export interface MemberTokenPayload {
  roomId: string;
  memberId: string;
  deviceId: string;
  exp: number;
}
