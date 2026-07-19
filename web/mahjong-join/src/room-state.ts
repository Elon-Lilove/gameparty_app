export type RoomMode = "multiplayer" | "solo";
export type RoomStatus = "active" | "ended";
export type ConnectionState = "connecting" | "connected" | "reconnecting";

export interface RoomInfo {
  code: string;
  title: string;
  status: RoomStatus;
  mode: RoomMode;
  ownerDeviceId: string;
  multiplier: number;
}

export interface Player {
  id: string;
  name: string;
  deviceId?: string | null;
  seat?: string | null;
  score: number;
  multiplierScore: number;
  result?: "win" | "lose" | "draw" | null;
  sortOrder: number;
  isActive: boolean;
}

export interface ScoreEvent {
  id: string;
  playerId: string;
  actorMemberId?: string | null;
  delta: number;
  reason?: string | null;
  scoreAfter: number;
  createdAt: string;
}

export interface Snapshot {
  room: RoomInfo;
  players: Player[];
  recentEvents: ScoreEvent[];
}

export type MutationType =
  | "adjust_score"
  | "add_player"
  | "give_score"
  | "table_score"
  | "rename_player"
  | "remove_player"
  | "transfer_owner";

export interface PendingOperation {
  id: string;
  type: MutationType;
  startedAt: number;
}

export interface RoomClientState {
  connection: ConnectionState;
  snapshot?: Snapshot;
  pending?: PendingOperation;
  settling?: boolean;
  error?: string;
}

export interface RoomEnvelope {
  type: string;
  snapshot?: Snapshot;
  error?: string;
  operationId?: string;
  actorDeviceId?: string;
}

export type ParseResult =
  | { ok: true; value: number }
  | { ok: false; message: string };

export function parseScoreAmount(raw: string): ParseResult {
  const value = Number(raw.trim());
  return Number.isInteger(value) && value >= 1 && value <= 1_000_000
    ? { ok: true, value }
    : { ok: false, message: "请输入 1 到 1000000 的整数" };
}

export function parseMultiplier(raw: string): ParseResult {
  const normalized = raw.trim();
  const value = Number(normalized);
  return normalized.length > 0 && Number.isFinite(value) && value > 0 && value <= 1_000_000
    ? { ok: true, value }
    : { ok: false, message: "倍率请输入大于 0 且不超过 1000000 的数字" };
}

export function beginOperation(type: MutationType, id: string): PendingOperation {
  return { type, id, startedAt: Date.now() };
}

export function applyEnvelope(
  state: RoomClientState,
  envelope: RoomEnvelope,
  currentDeviceId: string,
): RoomClientState {
  const acknowledgementMatches =
    Boolean(state.pending) &&
    envelope.operationId === state.pending?.id &&
    envelope.actorDeviceId === currentDeviceId;

  return {
    ...state,
    snapshot: envelope.snapshot ?? state.snapshot,
    pending: acknowledgementMatches ? undefined : state.pending,
    error: envelope.error ?? (acknowledgementMatches ? undefined : state.error),
  };
}

export function canSendMutation(state: RoomClientState): boolean {
  return state.connection === "connected" && state.snapshot?.room.status === "active" && !state.pending && !state.settling;
}

export function isOwner(snapshot: Snapshot, deviceId: string): boolean {
  return snapshot.room.ownerDeviceId === deviceId;
}

export function currentPlayer(snapshot: Snapshot, deviceId: string): Player | undefined {
  return snapshot.players.find((player) => player.isActive && player.deviceId === deviceId);
}

export function canGiveScore(snapshot: Snapshot, deviceId: string, targetPlayerId: string): boolean {
  const source = currentPlayer(snapshot, deviceId);
  const target = snapshot.players.find((player) => player.id === targetPlayerId && player.isActive);
  if (!source || !target || source.id === target.id) {
    return false;
  }
  return target.seat !== "table" && target.name !== "台板";
}
