import {
  canGiveScore,
  currentPlayer,
  isOwner,
  type ConnectionState,
  type PendingOperation,
  type Player,
  type Snapshot,
} from "./room-state";

export type RoomDialog =
  | { kind: "give"; targetPlayerId: string; value: string; error?: string }
  | { kind: "table"; value: string; error?: string }
  | { kind: "rename"; playerId: string; value: string; error?: string }
  | { kind: "settle"; value: string; error?: string }
  | { kind: "transfer"; error?: string };

export interface RoomViewOptions {
  deviceId: string;
  connection: ConnectionState;
  pending?: PendingOperation;
  error?: string;
  feedback?: string;
  tableEnabled: boolean;
  voiceEnabled: boolean;
  detailsVisible: boolean;
  settling?: boolean;
  dialog?: RoomDialog;
}

export function renderRoomView(snapshot: Snapshot, options: RoomViewOptions): string {
  const owner = isOwner(snapshot, options.deviceId);
  const self = currentPlayer(snapshot, options.deviceId);
  const canMutate =
    options.connection === "connected" && snapshot.room.status === "active" && !options.pending && !options.settling;
  const ownerCandidates = snapshot.players.filter(
    (player) => player.isActive && player.deviceId && player.deviceId !== options.deviceId && player.seat !== "table",
  );
  const activePlayers = snapshot.players.filter((player) => player.isActive);
  const hasTable = activePlayers.some((player) => player.seat === "table" || player.name === "台板");
  const visiblePlayers = [...activePlayers];
  if (options.tableEnabled && snapshot.room.status === "active" && !hasTable) {
    visiblePlayers.push({
      id: "__table_service__",
      name: "台板",
      deviceId: null,
      seat: "table",
      score: 0,
      multiplierScore: 0,
      result: null,
      sortOrder: Math.max(-1, ...activePlayers.map((player) => player.sortOrder)) + 1,
      isActive: true,
    });
  }

  return `
    <section class="room-screen">
      <header class="room-header">
        <div>
          <p class="eyebrow">${snapshot.room.mode === "solo" ? "单人模式" : "多人模式"}</p>
          <h1>${escapeHTML(snapshot.room.title)}</h1>
          <p class="room-code">房间号 ${escapeHTML(snapshot.room.code)}</p>
        </div>
        <span class="status ${snapshot.room.status}">${snapshot.room.status === "active" ? "进行中" : "已结算"}</span>
      </header>

      <section class="sync-strip" aria-live="polite">
        <span class="sync-dot ${options.connection}"></span>
        <span>${connectionLabel(options.connection)}</span>
        ${options.pending ? `<span class="pending-text"><span class="mini-loader"></span>${pendingLabel(options.pending.type)}</span>` : ""}
        ${options.feedback ? `<span class="success-text">✓ ${escapeHTML(options.feedback)}</span>` : ""}
      </section>

      ${options.error ? `<div class="room-error" role="alert"><span>${escapeHTML(options.error)}</span><button data-action="dismiss-error" aria-label="关闭错误">×</button></div>` : ""}

      <nav class="room-tools" aria-label="房间工具">
        ${renderRoomTool("invite", "invite", "＋", "玩家邀请")}
        ${
          owner && snapshot.room.mode === "multiplayer"
            ? renderRoomTool(
                "transfer",
                "open-transfer",
                "⇄",
                "房主转让",
                false,
                !canMutate || ownerCandidates.length === 0,
              )
            : ""
        }
        ${renderRoomTool("voice", "toggle-voice", "▶", "语音播放", options.voiceEnabled)}
        ${renderRoomTool("table", "toggle-table", "♨", "台板（茶水）", options.tableEnabled)}
      </nav>

      <section class="player-table" aria-label="玩家列表">
        <div class="player-row player-header"><span>玩家</span><span>得分</span><span>操作</span></div>
        <div class="table-message">${snapshot.room.status === "ended" ? "对局已结算" : "祝大家生活愉快！"}</div>
        ${visiblePlayers
          .sort((left, right) => left.sortOrder - right.sortOrder)
          .map((player) => renderPlayerRow(player, snapshot, options, canMutate))
          .join("")}
      </section>

      ${options.detailsVisible ? renderScoreDetails(snapshot) : ""}

      <footer class="room-bottom-bar">
        <button data-action="toggle-details">${options.detailsVisible ? "收起详情" : "给分详情"}</button>
        ${
          owner
            ? `<button class="primary" data-action="settle" ${!canMutate || options.settling ? "disabled" : ""}>${
                options.settling ? "结算中…" : snapshot.room.status === "ended" ? "已结算" : "结算房间"
              }</button>`
            : `<button class="primary" disabled>${snapshot.room.status === "ended" ? "已结算" : "房主结算"}</button>`
        }
      </footer>

      ${options.dialog ? renderDialog(snapshot, options.dialog, options.settling === true) : ""}
      ${!self ? `<p class="sr-only">当前设备没有活跃玩家</p>` : ""}
    </section>
  `;
}

function renderPlayerRow(
  player: Player,
  snapshot: Snapshot,
  options: RoomViewOptions,
  canMutate: boolean,
): string {
  const self = player.deviceId === options.deviceId;
  const owner = player.deviceId === snapshot.room.ownerDeviceId;
  const table = player.seat === "table" || player.name === "台板";
  const editable = canMutate && (self || isOwner(snapshot, options.deviceId)) && !table;
  const canGive = !table && canMutate && canGiveScore(snapshot, options.deviceId, player.id);
  const canGiveTable = table && canMutate && options.tableEnabled;
  const canRemove =
    canMutate &&
    isOwner(snapshot, options.deviceId) &&
    !self &&
    !owner &&
    !table &&
    Boolean(player.deviceId) &&
    player.score === 0;
  const removalBlockedByBalance =
    canMutate && isOwner(snapshot, options.deviceId) && !self && !owner && !table && Boolean(player.deviceId) && player.score !== 0;
  const score = snapshot.room.status === "ended" ? player.multiplierScore : player.score;
  const pendingForPlayer = options.pending?.type === "give_score";
  const pendingForTable = options.pending?.type === "table_score";
  const canLeave = self && !isOwner(snapshot, options.deviceId) && snapshot.room.status === "active";
  const leaveBlockedByBalance = canLeave && player.score !== 0;
  const actionButtons = [
    canGive
      ? `<button class="small prominent" data-give="${escapeHTML(player.id)}">${pendingForPlayer ? "等待" : "给分"}</button>`
      : "",
    canGiveTable
      ? `<button class="small prominent" data-table-give>${pendingForTable ? "等待" : "给分"}</button>`
      : "",
    canRemove ? `<button class="small danger-outline" data-remove="${escapeHTML(player.id)}">移除</button>` : "",
    canLeave
      ? `<button class="small danger-outline" data-action="leave" ${canMutate && !leaveBlockedByBalance ? "" : "disabled"}>退出</button>${
          leaveBlockedByBalance ? '<small class="action-note">分数归零后才能退出房间</small>' : ""
        }`
      : "",
    removalBlockedByBalance ? '<small class="action-note">归零后可移除</small>' : "",
  ].filter(Boolean);

  return `
    <div class="player-row ${self ? "me" : ""}">
      <button class="player-identity" data-rename="${escapeHTML(player.id)}" ${editable ? "" : "disabled"}>
        <span class="avatar">${escapeHTML(player.name.slice(0, 1))}</span>
        <span class="player-name">${escapeHTML(player.name)}
          ${self ? '<em class="badge self-badge">自己</em>' : ""}
          ${owner ? '<em class="badge owner-badge">房主</em>' : ""}
        </span>
      </button>
      <strong class="score">${formatScore(score)}</strong>
      <span class="player-action">${
        snapshot.room.status === "ended"
          ? resultLabel(player.result)
          : actionButtons.length > 0
            ? actionButtons.join("")
            : "—"
      }</span>
    </div>
  `;
}

function renderScoreDetails(snapshot: Snapshot): string {
  const events = snapshot.recentEvents.slice(0, 30);
  return `
    <section class="score-details" aria-label="给分详情">
      <h2>${snapshot.room.status === "ended" ? "结算详情" : "给分详情"}</h2>
      ${
        events.length === 0
          ? '<p class="empty-state">暂无给分记录</p>'
          : events
              .map((event) => {
                const player = snapshot.players.find((candidate) => candidate.id === event.playerId);
                return `<div class="event-row"><span>${escapeHTML(player?.name ?? "玩家")} · ${escapeHTML(event.reason ?? "给分")}</span><strong class="${event.delta >= 0 ? "positive" : "negative"}">${event.delta >= 0 ? "+" : ""}${event.delta}</strong><small>→ ${event.scoreAfter}</small></div>`;
              })
              .join("")
      }
    </section>
  `;
}

function renderDialog(snapshot: Snapshot, dialog: RoomDialog, settling: boolean): string {
  if (dialog.kind === "give") {
    const target = snapshot.players.find((player) => player.id === dialog.targetPlayerId);
    return dialogShell(
      `给 ${escapeHTML(target?.name ?? "玩家")} 分`,
      `<label>分数<input id="dialog-value" inputmode="numeric" value="${escapeHTML(dialog.value)}" autofocus></label>
       ${dialog.error ? `<p class="dialog-error">${escapeHTML(dialog.error)}</p>` : ""}
       <div class="dialog-actions"><button data-action="close-dialog">取消</button><button class="primary" data-action="confirm-give">确定</button></div>`,
    );
  }
  if (dialog.kind === "table") {
    return dialogShell(
      "台板（茶水）计分",
      `<label>分数<input id="dialog-value" inputmode="numeric" value="${escapeHTML(dialog.value)}" autofocus></label>
       ${dialog.error ? `<p class="dialog-error">${escapeHTML(dialog.error)}</p>` : ""}
       <div class="dialog-actions"><button data-action="close-dialog">取消</button><button class="primary" data-action="confirm-table">确定</button></div>`,
    );
  }
  if (dialog.kind === "rename") {
    return dialogShell(
      "修改名字",
      `<label>名字<input id="dialog-value" maxlength="24" value="${escapeHTML(dialog.value)}" autofocus></label>
       ${dialog.error ? `<p class="dialog-error">${escapeHTML(dialog.error)}</p>` : ""}
       <div class="dialog-actions"><button data-action="close-dialog">取消</button><button class="primary" data-action="confirm-rename">确定</button></div>`,
    );
  }
  if (dialog.kind === "settle") {
    return dialogShell(
      "输入倍率，快速结算！",
      `<label>倍率<input id="dialog-value" inputmode="decimal" value="${escapeHTML(dialog.value)}" autofocus></label>
       ${dialog.error ? `<p class="dialog-error">${escapeHTML(dialog.error)}</p>` : ""}
       <div class="dialog-actions"><button data-action="close-dialog" ${settling ? "disabled" : ""}>取消</button><button class="primary" data-action="confirm-settle" ${settling ? "disabled" : ""}>${settling ? "结算中…" : "确定"}</button></div>`,
    );
  }

  const candidates = snapshot.players.filter(
    (player) => player.isActive && player.deviceId && player.deviceId !== snapshot.room.ownerDeviceId && player.seat !== "table",
  );
  return dialogShell(
    "转让群主",
    `<div class="candidate-list">${candidates.map((player) => `<button data-transfer="${escapeHTML(player.deviceId ?? "")}">${escapeHTML(player.name)}</button>`).join("")}</div>
     ${dialog.error ? `<p class="dialog-error">${escapeHTML(dialog.error)}</p>` : ""}
     <div class="dialog-actions"><button data-action="close-dialog">取消</button></div>`,
  );
}

function dialogShell(title: string, body: string): string {
  return `<div class="modal-backdrop" data-action="close-dialog"><section class="dialog" role="dialog" aria-modal="true" aria-label="${escapeHTML(title)}" data-dialog-panel><h2>${escapeHTML(title)}</h2>${body}</section></div>`;
}

function renderRoomTool(
  key: string,
  action: string,
  icon: string,
  label: string,
  selected = false,
  disabled = false,
): string {
  return `<button class="room-tool${selected ? " selected" : ""}" data-tool="${escapeHTML(key)}" data-action="${escapeHTML(action)}" ${disabled ? "disabled" : ""}>
    <span class="tool-icon" aria-hidden="true">${escapeHTML(icon)}</span>
    <span class="tool-label">${escapeHTML(label)}</span>
  </button>`;
}

function connectionLabel(connection: ConnectionState): string {
  if (connection === "connected") return "实时同步中";
  if (connection === "reconnecting") return "正在重新连接";
  return "连接中";
}

function pendingLabel(type: PendingOperation["type"]): string {
  const labels: Record<PendingOperation["type"], string> = {
    adjust_score: "计分提交中",
    add_player: "添加中",
    give_score: "给分中",
    table_score: "台板计分中",
    rename_player: "改名中",
    remove_player: "正在退出",
    transfer_owner: "转让中",
  };
  return labels[type];
}

function resultLabel(result: Player["result"]): string {
  if (result === "win") return "胜利";
  if (result === "lose") return "失败";
  if (result === "draw") return "平局";
  return "—";
}

function formatScore(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2);
}

export function escapeHTML(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => {
    const entities: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      "'": "&#39;",
      '"': "&quot;",
    };
    return entities[character] ?? character;
  });
}
