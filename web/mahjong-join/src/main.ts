import "./styles.css";
import {
  applyEnvelope,
  beginOperation,
  canSendMutation,
  currentPlayer,
  parseMultiplier,
  parseScoreAmount,
  type MutationType,
  type RoomClientState,
  type RoomEnvelope,
  type RoomInfo,
  type Snapshot,
} from "./room-state";
import { escapeHTML, renderRoomView, type RoomDialog } from "./room-view";

interface JoinResponse {
  memberToken: string;
  snapshot: Snapshot;
}

interface RecentRoom {
  code: string;
  title: string;
  updatedAt: number;
}

interface AppState extends RoomClientState {
  code: string;
  deviceId: string;
  memberToken?: string;
  socket?: WebSocket;
  hasLeft: boolean;
  reconnectTimer?: number;
  operationTimer?: number;
  feedback?: string;
  feedbackTimer?: number;
  tableEnabled: boolean;
  voiceEnabled: boolean;
  detailsVisible: boolean;
  settling: boolean;
  dialog?: RoomDialog;
  knownEventIds: Set<string>;
}

const API_BASE_URL = import.meta.env.VITE_MAHJONG_API_BASE_URL ?? "/api";
const WEBSOCKET_BASE_URL = import.meta.env.VITE_MAHJONG_WEBSOCKET_BASE_URL ?? "https://mahjong-score-worker.d03054144.workers.dev";
const DEVICE_ID_KEY = "mahjong-score-device-id";
const TOKEN_KEY_PREFIX = "mahjong-score-token-";
const RECENT_ROOMS_KEY = "mahjong-score-recent-rooms";
const TABLE_ENABLED_KEY = "mahjong-score-table-enabled";
const VOICE_ENABLED_KEY = "mahjong-score-voice-enabled";

const app = document.querySelector<HTMLMainElement>("#app");
if (!app) {
  throw new Error("Missing app root");
}

const state: AppState = {
  code: new URLSearchParams(location.search).get("room")?.trim().toUpperCase() ?? "",
  deviceId: getDeviceId(),
  connection: "connecting",
  hasLeft: false,
  tableEnabled: localStorage.getItem(TABLE_ENABLED_KEY) === "true",
  voiceEnabled: localStorage.getItem(VOICE_ENABLED_KEY) === "true",
  detailsVisible: false,
  settling: false,
  knownEventIds: new Set<string>(),
};

class JoinRoomError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "JoinRoomError";
  }
}

void start();

async function start(): Promise<void> {
  if (!state.code) {
    renderRecentRooms();
    return;
  }

  clearReconnectTimer();
  clearOperationTimer();
  state.error = undefined;
  state.feedback = undefined;
  state.hasLeft = false;
  state.pending = undefined;
  state.connection = "connecting";
  state.socket?.close();
  renderLoading();

  try {
    const joined = await joinRoom(state.code);
    state.memberToken = joined.memberToken;
    state.snapshot = joined.snapshot;
    state.knownEventIds = new Set(joined.snapshot.recentEvents.map((event) => event.id));
    localStorage.setItem(`${TOKEN_KEY_PREFIX}${state.code}`, joined.memberToken);
    saveRecentRoom(joined.snapshot.room);
    connectWebSocket();
    render();
  } catch (error) {
    state.error = error instanceof Error ? error.message : "网络连接似乎出现问题，请稍后重试。";
    render();
  }
}

async function joinRoom(code: string): Promise<JoinResponse> {
  try {
    const existingToken = localStorage.getItem(`${TOKEN_KEY_PREFIX}${code}`);
    const response = await fetch(`${API_BASE_URL}/rooms/${encodeURIComponent(code)}/join`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(existingToken ? { authorization: `Bearer ${existingToken}` } : {}),
      },
      body: JSON.stringify({ deviceId: state.deviceId, displayName: defaultDisplayName() }),
    });
    if (!response.ok) {
      const payload = (await response.json().catch(() => null)) as { error?: string } | null;
      const serverMessage = payload?.error ?? "";

      if (response.status === 409 || /room is not active/i.test(serverMessage)) {
        throw new JoinRoomError("房间已结束，无法再加入。", response.status);
      }
      if (response.status === 404) {
        throw new JoinRoomError("房间不存在，请让房主重新生成邀请链接。", response.status);
      }
      if (response.status === 403 && /membership/i.test(serverMessage)) {
        throw new JoinRoomError("你已被移出房间，无法使用原身份重新加入。", response.status);
      }
      if (response.status === 401) {
        throw new JoinRoomError("房间身份无法验证，请让房主移除旧成员后重新加入。", response.status);
      }

      throw new JoinRoomError(friendlyServerMessage(serverMessage), response.status);
    }

    return response.json() as Promise<JoinResponse>;
  } catch (error) {
    if (error instanceof JoinRoomError) {
      throw error;
    }
    throw new Error("网络连接似乎出现问题，请检查网络后重试。");
  }
}

function connectWebSocket(): void {
  if (!state.memberToken) {
    return;
  }

  clearReconnectTimer();
  state.socket?.close();
  state.connection = "connecting";
  const socket = new WebSocket(createWebSocketURL(state.code, state.memberToken));
  state.socket = socket;
  render();

  socket.addEventListener("open", () => {
    if (state.socket !== socket) return;
    state.connection = "connected";
    state.error = undefined;
    render();
  });

  socket.addEventListener("message", (event) => {
    if (state.socket !== socket) return;
    const envelope = JSON.parse(String(event.data)) as RoomEnvelope;
    const previousSnapshot = state.snapshot;
    const completedOperation =
      state.pending &&
      envelope.operationId === state.pending.id &&
      envelope.actorDeviceId === state.deviceId;

    Object.assign(state, applyEnvelope(state, envelope, state.deviceId));

    if (envelope.type === "state" && envelope.snapshot) {
      state.connection = "connected";
      state.hasLeft = !envelope.snapshot.players.some(
        (player) => player.isActive && player.deviceId === state.deviceId,
      );
      if (state.hasLeft) {
        localStorage.removeItem(`${TOKEN_KEY_PREFIX}${state.code}`);
        socket.close(1000, "Membership removed");
      }
      saveRecentRoom(envelope.snapshot.room);
      announceNewEvents(previousSnapshot, envelope.snapshot);
      if (completedOperation) {
        clearOperationTimer();
        showFeedback("操作成功");
      }
    }

    if (envelope.type === "error" && envelope.error) {
      if (completedOperation) clearOperationTimer();
      state.error = friendlyServerMessage(envelope.error);
    }
    render();
  });

  socket.addEventListener("error", () => {
    if (state.socket !== socket) return;
    state.connection = "reconnecting";
    state.error = "网络连接似乎出现问题，正在自动重连";
    render();
  });

  socket.addEventListener("close", () => {
    if (state.socket !== socket) return;
    state.socket = undefined;
    if (state.pending) {
      state.pending = undefined;
      clearOperationTimer();
      state.error = "连接中断，操作未确认，请重连后重试";
    }
    if (!state.hasLeft && state.snapshot?.room.status === "active") {
      state.connection = "reconnecting";
      state.reconnectTimer = window.setTimeout(connectWebSocket, 1500);
    }
    render();
  });
}

function createWebSocketURL(code: string, memberToken: string): string {
  const url = new URL(WEBSOCKET_BASE_URL, location.origin);
  url.protocol = url.protocol === "http:" ? "ws:" : "wss:";
  url.pathname = `${url.pathname.replace(/\/$/, "")}/rooms/${encodeURIComponent(code)}/ws`;
  url.search = new URLSearchParams({ memberToken }).toString();
  return url.toString();
}

function sendMutation(type: MutationType, payload: Record<string, unknown>): boolean {
  if (!canSendMutation(state) || state.socket?.readyState !== WebSocket.OPEN) {
    state.error = "实时同步正在连接，请稍后再试";
    render();
    return false;
  }

  const operationId = crypto.randomUUID();
  state.pending = beginOperation(type, operationId);
  state.error = undefined;
  state.feedback = undefined;
  render();

  try {
    state.socket.send(JSON.stringify({ type, ...payload, operationId }));
  } catch {
    state.pending = undefined;
    state.error = "操作发送失败，请重试";
    render();
    return false;
  }

  clearOperationTimer();
  state.operationTimer = window.setTimeout(() => {
    if (state.pending?.id !== operationId) return;
    state.pending = undefined;
    state.error = "操作未确认，请检查网络后重试";
    render();
  }, 8000);
  return true;
}

function render(): void {
  if (state.error && !state.snapshot) {
    app.innerHTML = `
      <section class="screen center">
        <h1>麻将计分器</h1>
        <p class="error">${escapeHTML(state.error)}</p>
        <button class="primary" id="retry">重试</button>
      </section>
    `;
    document.querySelector("#retry")?.addEventListener("click", () => void start());
    return;
  }

  const snapshot = state.snapshot;
  if (!snapshot) {
    renderLoading();
    return;
  }

  const self = currentPlayer(snapshot, state.deviceId);
  if (!self || state.hasLeft) {
    app.innerHTML = `
      <section class="screen center">
        <h1>${escapeHTML(snapshot.room.code)} 房间</h1>
        <p>你已退出或被移出房间</p>
        <p>如需再次参与，请联系房主使用新的玩家身份加入。</p>
      </section>
    `;
    return;
  }

  app.innerHTML = renderRoomView(snapshot, {
    deviceId: state.deviceId,
    connection: state.connection,
    pending: state.pending,
    error: state.error,
    feedback: state.feedback,
    tableEnabled: state.tableEnabled,
    voiceEnabled: state.voiceEnabled,
    detailsVisible: state.detailsVisible,
    settling: state.settling,
    dialog: state.dialog,
  });
  wireRoomEvents(snapshot);
}

function wireRoomEvents(snapshot: Snapshot): void {
  bindAction("dismiss-error", () => {
    state.error = undefined;
    render();
  });
  bindAction("invite", () => void copyInviteLink());
  bindAction("toggle-voice", () => {
    state.voiceEnabled = !state.voiceEnabled;
    localStorage.setItem(VOICE_ENABLED_KEY, String(state.voiceEnabled));
    showFeedback(state.voiceEnabled ? "语音播报已开启" : "语音播报已关闭");
    render();
  });
  bindAction("toggle-table", () => {
    state.tableEnabled = !state.tableEnabled;
    localStorage.setItem(TABLE_ENABLED_KEY, String(state.tableEnabled));
    render();
  });
  bindAction("toggle-details", () => {
    state.detailsVisible = !state.detailsVisible;
    render();
  });
  bindAction("open-transfer", () => {
    state.dialog = { kind: "transfer" };
    render();
  });
  bindAction("settle", () => {
    state.dialog = { kind: "settle", value: String(snapshot.room.multiplier || 1) };
    render();
  });
  bindAction("leave", () => {
    const self = currentPlayer(snapshot, state.deviceId);
    if (self && window.confirm("确定退出房间？")) {
      sendMutation("remove_player", { playerId: self.id });
    }
  });

  document.querySelectorAll<HTMLButtonElement>("[data-give]").forEach((button) => {
    button.addEventListener("click", () => {
      const targetPlayerId = button.dataset.give;
      if (!targetPlayerId) return;
      state.dialog = { kind: "give", targetPlayerId, value: "1" };
      render();
    });
  });

  document.querySelectorAll<HTMLButtonElement>("[data-remove]").forEach((button) => {
    button.addEventListener("click", () => {
      const playerId = button.dataset.remove;
      const player = snapshot.players.find((candidate) => candidate.id === playerId);
      if (playerId && player && window.confirm(`确定移除 ${player.name}？`)) {
        sendMutation("remove_player", { playerId });
      }
    });
  });

  document.querySelectorAll<HTMLButtonElement>("[data-rename]").forEach((button) => {
    button.addEventListener("click", () => {
      const playerId = button.dataset.rename;
      const player = snapshot.players.find((candidate) => candidate.id === playerId);
      if (!playerId || !player) return;
      state.dialog = { kind: "rename", playerId, value: player.name };
      render();
    });
  });

  document.querySelectorAll<HTMLButtonElement>("[data-table-give]").forEach((button) => {
    button.addEventListener("click", () => {
      state.dialog = { kind: "table", value: "1" };
      render();
    });
  });

  document.querySelectorAll<HTMLButtonElement>("[data-transfer]").forEach((button) => {
    button.addEventListener("click", () => {
      const targetDeviceId = button.dataset.transfer;
      if (targetDeviceId && sendMutation("transfer_owner", { targetDeviceId })) {
        state.dialog = undefined;
        render();
      }
    });
  });

  document.querySelectorAll<HTMLElement>("[data-action=\"close-dialog\"]").forEach((element) => {
    element.addEventListener("click", (event) => {
      if (element.classList.contains("modal-backdrop") && event.target !== element) return;
      if (state.settling) return;
      state.dialog = undefined;
      render();
    });
  });

  bindAction("confirm-give", () => confirmGive());
  bindAction("confirm-table", () => confirmTableScore());
  bindAction("confirm-rename", () => confirmRename());
  bindAction("confirm-settle", () => void confirmSettlement());
}

function confirmGive(): void {
  if (state.dialog?.kind !== "give") return;
  const raw = dialogInputValue();
  const result = parseScoreAmount(raw);
  if (!result.ok) {
    state.dialog = { ...state.dialog, value: raw, error: result.message };
    render();
    return;
  }
  if (sendMutation("give_score", { targetPlayerId: state.dialog.targetPlayerId, amount: result.value })) {
    state.dialog = undefined;
    render();
  }
}

function confirmTableScore(): void {
  if (state.dialog?.kind !== "table") return;
  const raw = dialogInputValue();
  const result = parseScoreAmount(raw);
  if (!result.ok) {
    state.dialog = { ...state.dialog, value: raw, error: result.message };
    render();
    return;
  }
  if (sendMutation("table_score", { amount: result.value })) {
    state.dialog = undefined;
    render();
  }
}

function confirmRename(): void {
  if (state.dialog?.kind !== "rename") return;
  const value = dialogInputValue().trim();
  if (!value) {
    state.dialog = { ...state.dialog, value, error: "名字不能为空" };
    render();
    return;
  }
  if (sendMutation("rename_player", { playerId: state.dialog.playerId, name: value.slice(0, 24) })) {
    state.dialog = undefined;
    render();
  }
}

async function confirmSettlement(): Promise<void> {
  if (state.dialog?.kind !== "settle" || !state.memberToken || state.settling) return;
  if (!canSendMutation(state)) {
    state.dialog = { ...state.dialog, error: "房间状态正在同步，请稍后再试" };
    render();
    return;
  }
  const raw = dialogInputValue();
  const result = parseMultiplier(raw);
  if (!result.ok) {
    state.dialog = { ...state.dialog, value: raw, error: result.message };
    render();
    return;
  }

  state.settling = true;
  state.error = undefined;
  render();
  try {
    const response = await fetch(`${API_BASE_URL}/rooms/${encodeURIComponent(state.code)}/settle`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${state.memberToken}`,
      },
      body: JSON.stringify({ multiplier: result.value }),
    });
    const payload = (await response.json().catch(() => null)) as { snapshot?: Snapshot; error?: string } | null;
    if (!response.ok || !payload?.snapshot) {
      throw new Error(friendlyServerMessage(payload?.error ?? "结算失败，请稍后重试"));
    }
    state.snapshot = payload.snapshot;
    state.dialog = undefined;
    state.detailsVisible = true;
    showFeedback("结算成功");
  } catch (error) {
    const message = error instanceof Error ? error.message : "结算失败，请稍后重试";
    state.error = message;
    state.dialog = { kind: "settle", value: raw, error: message };
  } finally {
    state.settling = false;
    render();
  }
}

function bindAction(action: string, handler: () => void): void {
  document.querySelector<HTMLElement>(`[data-action="${action}"]`)?.addEventListener("click", handler);
}

function dialogInputValue(): string {
  return document.querySelector<HTMLInputElement>("#dialog-value")?.value ?? "";
}

async function copyInviteLink(): Promise<void> {
  const url = new URL(location.href);
  url.search = new URLSearchParams({ room: state.code }).toString();
  try {
    await navigator.clipboard.writeText(url.toString());
    showFeedback("邀请链接已复制");
  } catch {
    state.error = "复制失败，请手动复制浏览器地址";
  }
  render();
}

function announceNewEvents(previous: Snapshot | undefined, next: Snapshot): void {
  const previousIds = new Set(previous?.recentEvents.map((event) => event.id) ?? state.knownEventIds);
  const newEvents = next.recentEvents.filter((event) => !previousIds.has(event.id));
  state.knownEventIds = new Set(next.recentEvents.map((event) => event.id));
  if (!state.voiceEnabled || !("speechSynthesis" in window)) return;

  for (const event of newEvents.reverse()) {
    if (event.delta <= 0) continue;
    const player = next.players.find((candidate) => candidate.id === event.playerId);
    window.speechSynthesis.speak(new SpeechSynthesisUtterance(`${player?.name ?? "玩家"}加${event.delta}分`));
  }
}

function renderRecentRooms(): void {
  const rooms = loadRecentRooms();
  app.innerHTML = `
    <section class="screen">
      <header class="topbar"><div><p class="eyebrow">麻将计分器</p><h1>最近房间</h1></div></header>
      ${
        rooms.length > 0
          ? `<section class="recent-list">${rooms
              .map(
                (room) => `<button class="recent-room" data-room="${escapeHTML(room.code)}"><span><strong>${escapeHTML(room.code)} 房间</strong><small>${escapeHTML(room.title)}</small></span><span>返回</span></button>`,
              )
              .join("")}</section>`
          : `<section class="empty-card"><p>暂无最近房间</p><strong>请先扫码加入房间</strong></section>`
      }
    </section>
  `;
  document.querySelectorAll<HTMLButtonElement>("[data-room]").forEach((button) => {
    button.addEventListener("click", () => {
      state.code = button.dataset.room ?? "";
      history.replaceState(null, "", `?room=${encodeURIComponent(state.code)}`);
      void start();
    });
  });
}

function renderLoading(): void {
  app.innerHTML = `<section class="screen center"><div class="loader"></div><p>正在加入房间...</p></section>`;
}

function showFeedback(message: string): void {
  window.clearTimeout(state.feedbackTimer);
  state.feedback = message;
  state.feedbackTimer = window.setTimeout(() => {
    state.feedback = undefined;
    render();
  }, 1800);
}

function clearReconnectTimer(): void {
  window.clearTimeout(state.reconnectTimer);
  state.reconnectTimer = undefined;
}

function clearOperationTimer(): void {
  window.clearTimeout(state.operationTimer);
  state.operationTimer = undefined;
}

function getDeviceId(): string {
  const existing = localStorage.getItem(DEVICE_ID_KEY);
  if (existing) return existing;
  const generated = crypto.randomUUID();
  localStorage.setItem(DEVICE_ID_KEY, generated);
  return generated;
}

function defaultDisplayName(): string {
  return `玩家${state.deviceId.replaceAll("-", "").slice(-4).toUpperCase()}`;
}

function loadRecentRooms(): RecentRoom[] {
  try {
    const raw = localStorage.getItem(RECENT_ROOMS_KEY);
    if (!raw) return [];
    const rooms = JSON.parse(raw) as RecentRoom[];
    return Array.isArray(rooms) ? rooms.slice(0, 8) : [];
  } catch {
    return [];
  }
}

function saveRecentRoom(room: RoomInfo): void {
  const rooms = loadRecentRooms().filter((candidate) => candidate.code !== room.code);
  rooms.unshift({ code: room.code, title: room.title || "麻将计分", updatedAt: Date.now() });
  localStorage.setItem(RECENT_ROOMS_KEY, JSON.stringify(rooms.slice(0, 8)));
}

function friendlyServerMessage(message: string): string {
  if (/Only the room owner can settle/i.test(message)) return "只有房主可以结算房间";
  if (/Only the room owner can transfer/i.test(message)) return "只有房主可以转让群主";
  if (/Room is not active/i.test(message)) return "房间已经结算，不能继续操作";
  if (/membership is no longer active|Membership was removed/i.test(message)) return "你已被移出房间";
  if (/balance must be zero/i.test(message)) return "该玩家分数需先结清为 0，才能移出房间";
  if (/Acting player not found/i.test(message)) return "当前玩家身份已失效，请重新加入";
  return message || "请求失败，请稍后重试";
}
