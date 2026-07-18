# Feishu Game Metadata Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorder the main Feishu game view, migrate source URLs out of gameplay descriptions, and populate evaluated player and duration ranges for every valid game.

**Architecture:** Treat the existing Feishu Base as the source of truth. Reuse the existing `链接`, player-count, and time fields; update only the `所有反馈` view order and the 18 valid game records, then verify all invariants by reading the Base back from Feishu.

**Tech Stack:** Feishu Base, `lark-cli base +...` shortcuts, user identity OAuth.

## Global Constraints

- Only `所有反馈` (`vew2IwHmj4`) receives the new visible-field order.
- The other three views keep their current visible-field configurations.
- The 8 date-only placeholder records are not modified.
- Source URLs move to `链接`; `description` contains gameplay text only.
- Player counts include a required participating or continuously active host.
- `time_min` and `time_max` are integer minutes for one normal play session.
- Every range must satisfy `min <= max`.
- Do not upload or copy source images.

---

### Task 1: Preflight Snapshot and Target Selection

**Files:**
- Read: `docs/superpowers/specs/2026-07-18-feishu-game-metadata-normalization-design.md`
- Modify: no application files; this task reads Feishu only

**Interfaces:**
- Consumes: Base token `PSxwbNUEMajAo3seqWicFAqsnUH`, table `tblCkPcGwjLMlxRw`, view `vew2IwHmj4`
- Produces: verified field IDs, current view order, and the exact 18 target record IDs

- [ ] **Step 1: Confirm fields and types**

Run:

```bash
lark-cli base +field-list \
  --base-token PSxwbNUEMajAo3seqWicFAqsnUH \
  --table-id tblCkPcGwjLMlxRw \
  --format json
```

Expected: `description` and `链接` are text fields; `链接.style.type` is `url`; `players_min`, `players_max`, `time_min`, and `time_max` are number fields.

- [ ] **Step 2: Confirm the current main-view order**

Run:

```bash
lark-cli base +view-get-visible-fields \
  --base-token PSxwbNUEMajAo3seqWicFAqsnUH \
  --table-id tblCkPcGwjLMlxRw \
  --view-id vew2IwHmj4 \
  --format json
```

Expected: 13 visible fields are returned and `name` is the first field.

- [ ] **Step 3: Read all target metadata**

Run:

```bash
lark-cli base +record-list \
  --base-token PSxwbNUEMajAo3seqWicFAqsnUH \
  --table-id tblCkPcGwjLMlxRw \
  --field-id name \
  --field-id description \
  --field-id 链接 \
  --field-id players_min \
  --field-id players_max \
  --field-id time_min \
  --field-id time_max \
  --limit 200 \
  --format json
```

Expected: `has_more` is `false`; there are 18 valid named game records and 8 date-only placeholder records. The 17 imported descriptions contain either a real newline or the literal characters `\\n` before `【内部来源】`.

- [ ] **Step 4: Verify the exact target IDs**

Expected name-to-ID mapping:

| Game | Record ID |
|---|---|
| 真真假假 | `rectgkBKRY` |
| 谁是贪吃鬼 | `recvpGWuWaP2SQ` |
| 含茶传话 | `recvpGWC12x2GE` |
| 确认过眼神 | `recvpGWC0R5nPA` |
| 歌词中的朋友 | `recvpGWC10Ay9c` |
| 你来我往 | `recvpGWC1kkJaz` |
| 土豆土堆腿肚子 | `recvpGWCtVcdge` |
| 沙漠里有几只猴 | `recvpGWCtJpfTy` |
| 真假抛球 | `recvpGWCu7pG8j` |
| emoji猜诗词 | `recvpGWCu3yysZ` |
| 抓鸭子 | `recvpGWCXj8IWj` |
| 加字游戏 | `recvpGWCXeJDA7` |
| 红萝卜蹲白萝卜 | `recvpGWCXFEW0v` |
| 姓名游戏 | `recvpGWCXNtWhU` |
| 三词造句 | `recvpGWDHYB2G8` |
| 数马游戏 | `recvpGWDI7QyB2` |
| 没有你我他 | `recvpGWDI6qjBv` |
| 大西瓜小西瓜 | `recvpGWDIkFuNc` |

If a name points to a different record ID, stop and rebuild the mapping from the fresh response before writing.

---

### Task 2: Reorder the Main View

**Files:**
- Modify: Feishu view `vew2IwHmj4` only

**Interfaces:**
- Consumes: verified 13-field list from Task 1
- Produces: the approved main-view column order

- [ ] **Step 1: Apply the exact visible-field order**

Run:

```bash
lark-cli base +view-set-visible-fields \
  --base-token PSxwbNUEMajAo3seqWicFAqsnUH \
  --table-id tblCkPcGwjLMlxRw \
  --view-id vew2IwHmj4 \
  --json '{"visible_fields":["name","description","emotion","players_min","players_max","tool","time_min","time_max","icon_homepage","icon_detailpage","state","链接","附件"]}' \
  --format json
```

Expected: the command succeeds and returns the updated visible-field configuration.

- [ ] **Step 2: Read the view order back**

Run the Task 1 Step 2 command again.

Expected exact order:

```json
["name","description","emotion","players_min","players_max","tool","time_min","time_max","icon_homepage","icon_detailpage","state","链接","附件"]
```

---

### Task 3: Migrate Links and Populate Evaluated Ranges

**Files:**
- Modify: 18 Feishu records listed below

**Interfaces:**
- Consumes: current descriptions and verified record IDs from Task 1
- Produces: clean descriptions, source URLs in `链接`, and complete integer ranges

- [ ] **Step 1: Use the approved evaluation matrix**

| Game | players_min | players_max | time_min | time_max | Link migration |
|---|---:|---:|---:|---:|---|
| 真真假假 | 3 | 10 | 10 | 20 | Keep blank |
| 谁是贪吃鬼 | 4 | 10 | 10 | 20 | Migrate |
| 确认过眼神 | 4 | 12 | 5 | 15 | Migrate |
| 你来我往 | 4 | 13 | 10 | 20 | Migrate |
| 歌词中的朋友 | 4 | 12 | 10 | 20 | Migrate |
| 含茶传话 | 6 | 16 | 10 | 20 | Migrate |
| 真假抛球 | 4 | 12 | 5 | 15 | Migrate |
| emoji猜诗词 | 3 | 12 | 10 | 25 | Migrate |
| 土豆土堆腿肚子 | 4 | 15 | 5 | 15 | Migrate |
| 沙漠里有几只猴 | 5 | 20 | 5 | 15 | Migrate |
| 加字游戏 | 3 | 10 | 10 | 20 | Migrate |
| 姓名游戏 | 4 | 15 | 10 | 20 | Migrate |
| 抓鸭子 | 4 | 15 | 5 | 15 | Migrate |
| 红萝卜蹲白萝卜 | 4 | 15 | 5 | 15 | Migrate |
| 大西瓜小西瓜 | 3 | 12 | 5 | 15 | Migrate |
| 没有你我他 | 3 | 12 | 10 | 20 | Migrate |
| 数马游戏 | 3 | 12 | 5 | 15 | Migrate |
| 三词造句 | 3 | 10 | 10 | 20 | Migrate |

- [ ] **Step 2: Update 真真假假 without inventing a source**

Run:

```bash
lark-cli base +record-upsert \
  --base-token PSxwbNUEMajAo3seqWicFAqsnUH \
  --table-id tblCkPcGwjLMlxRw \
  --record-id rectgkBKRY \
  --json '{"players_min":3,"players_max":10,"time_min":10,"time_max":20}' \
  --format json
```

Expected: the record is updated; `链接` remains empty.

- [ ] **Step 3: Update the 17 imported games serially**

Run the following exact serial update script. It passes JSON as an argument array, not through shell interpolation.

```bash
node <<'NODE'
const { spawnSync } = require("node:child_process");

const baseToken = "PSxwbNUEMajAo3seqWicFAqsnUH";
const tableId = "tblCkPcGwjLMlxRw";
const source = "https://www.xiaohongshu.com/explore/6991eec0000000001a02110c";
const updates = [
  {
    id: "recvpGWuWaP2SQ",
    name: "谁是贪吃鬼",
    description: "准备几种食物，由一名玩家秘密吃掉其中一种，其他玩家观察线索并猜出谁是“贪吃鬼”。猜中则贪吃鬼失败，未猜中则贪吃鬼获胜。",
    players_min: 4, players_max: 10, time_min: 10, time_max: 20,
  },
  {
    id: "recvpGWC0R5nPA",
    name: "确认过眼神",
    description: "所有人先低头，口令后同时抬头并注视一名玩家；若两人对视，双方立即喊出对方名字，较慢者淘汰，最后留下的玩家获胜。",
    players_min: 4, players_max: 12, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWC1kkJaz",
    name: "你来我往",
    description: "每三人组成一组，主持人提出一个问题，组内三名玩家依次各说一个字，三个字必须连成一句合理回答；无法衔接或回答不通顺的一组接受惩罚。",
    players_min: 4, players_max: 13, time_min: 10, time_max: 20,
  },
  {
    id: "recvpGWC10Ay9c",
    name: "歌词中的朋友",
    description: "选定一名玩家作为描述对象，其他人轮流唱出能形容他的歌词；重复、停顿过久或无法接唱者淘汰，最后留下的玩家获胜。",
    players_min: 4, players_max: 12, time_min: 10, time_max: 20,
  },
  {
    id: "recvpGWC12x2GE",
    name: "含茶传话",
    description: "玩家分成两队排成纵列，每队第一人口含一小口水，听清指定句子后依次向后传话；最后一人复述内容，与原句最接近的队伍获胜。",
    players_min: 6, players_max: 16, time_min: 10, time_max: 20,
  },
  {
    id: "recvpGWCu7pG8j",
    name: "真假抛球",
    description: "玩家站成半圆，用纸球进行真抛或假抛。抛球者可用假动作迷惑指定玩家；接球者误判动作或未接住真球即淘汰，最后留下者获胜。",
    players_min: 4, players_max: 12, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWCu3yysZ",
    name: "emoji猜诗词",
    description: "主持人依次展示由表情符号组成的提示，玩家抢答对应的诗句或词句；答对得分，答错可将机会让给其他玩家，最终得分最高者获胜。",
    players_min: 3, players_max: 12, time_min: 10, time_max: 25,
  },
  {
    id: "recvpGWCtVcdge",
    name: "土豆土堆腿肚子",
    description: "所有人按顺序快速循环说“土豆、土堆、腿肚子”，每次说完同时指向下一名玩家；说错词、停顿或指错人者淘汰。",
    players_min: 4, players_max: 15, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWCtJpfTy",
    name: "沙漠里有几只猴",
    description: "主持人喊出“沙漠里有几只猴”并给出数量，从指定玩家开始按顺时针由相应人数迅速站起，同时做出猴子挠头动作；人数或动作错误者接受惩罚。",
    players_min: 5, players_max: 20, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWCXeJDA7",
    name: "加字游戏",
    description: "第一名玩家说出一个字，后续玩家每轮在已有内容上增加一个字，并保证整句话通顺合理；重复、超时或无法组成句子者淘汰。",
    players_min: 3, players_max: 10, time_min: 10, time_max: 20,
  },
  {
    id: "recvpGWCXNtWhU",
    name: "姓名游戏",
    description: "玩家围成一圈，每人依次说出前面所有人的姓名并模仿对应动作，再加入自己的姓名和新动作；遗漏、说错或做错动作者淘汰。",
    players_min: 4, players_max: 15, time_min: 10, time_max: 20,
  },
  {
    id: "recvpGWCXj8IWj",
    name: "抓鸭子",
    description: "所有人按节奏依次接话：“抓鸭子”“抓几只”“抓三只”“抓到了”或“没抓到”。若说“抓到了”，后续玩家需按数量依次发出鸭叫；接错、漏接或数量错误者接受惩罚。",
    players_min: 4, players_max: 15, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWCXFEW0v",
    name: "红萝卜蹲白萝卜",
    description: "第一名玩家边说“红萝卜蹲”边完成下蹲动作，并指向下一人；被指到者立刻说“白萝卜蹲”并继续传递，反应慢、叫错或动作错误者淘汰。",
    players_min: 4, players_max: 15, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWDIkFuNc",
    name: "大西瓜小西瓜",
    description: "玩家依次说“大西瓜”或“小西瓜”，同时做出与口令相反大小的手势：喊大西瓜比小手势，喊小西瓜比大手势；口令、手势或节奏出错者接受惩罚。",
    players_min: 3, players_max: 12, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWDI6qjBv",
    name: "没有你我他",
    description: "玩家轮流唱歌，歌词中不能出现“你、我、他”三个字，可用动作或其他词替代；唱出禁用字、重复歌曲或停顿过久者接受惩罚。",
    players_min: 3, players_max: 12, time_min: 10, time_max: 20,
  },
  {
    id: "recvpGWDI7QyB2",
    name: "数马游戏",
    description: "主持人通过拍手制造干扰，然后问“现在有几匹马”等问题；答案不是拍手次数，而是问题句子的字数。玩家猜出规律后继续观察，未发现规律者接受挑战。",
    players_min: 3, players_max: 12, time_min: 5, time_max: 15,
  },
  {
    id: "recvpGWDHYB2G8",
    name: "三词造句",
    description: "每轮随机抽取三个互不相关的词语，玩家需在一分钟内把三个词全部放入一句通顺且有逻辑的话中；超时、漏词或句子不成立者淘汰。",
    players_min: 3, players_max: 10, time_min: 10, time_max: 20,
  },
];

for (const item of updates) {
  const patch = {
    description: item.description,
    "链接": source,
    players_min: item.players_min,
    players_max: item.players_max,
    time_min: item.time_min,
    time_max: item.time_max,
  };
  const result = spawnSync("lark-cli", [
    "base", "+record-upsert",
    "--base-token", baseToken,
    "--table-id", tableId,
    "--record-id", item.id,
    "--json", JSON.stringify(patch),
    "--format", "json",
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${item.name}: ${result.stderr || result.stdout}`);
  }
  const response = JSON.parse(result.stdout);
  if (!response.ok) throw new Error(`${item.name}: ${result.stdout}`);
  process.stdout.write(`${item.name}: ok\n`);
}
NODE
```

Expected: 17 lines ending in `: ok`. Each update returns the same record ID and no `ignored_fields`.

- [ ] **Step 4: Confirm no placeholder record was included**

Expected: every updated record ID is one of the 18 IDs in Task 1 Step 4; no record whose `name` is `2026/12/01` is updated.

---

### Task 4: Full Readback Verification

**Files:**
- Read: Feishu table and view
- Modify: no resources unless verification finds a mismatch

**Interfaces:**
- Consumes: all writes from Tasks 2 and 3
- Produces: evidence that every approved invariant holds

- [ ] **Step 1: Read all relevant record fields back**

Run the Task 1 Step 3 command again.

Expected: `has_more` is `false` and exactly 18 valid game records are returned alongside the 8 untouched placeholders.

- [ ] **Step 2: Validate record invariants**

Check all 18 valid records:

- `players_min`, `players_max`, `time_min`, and `time_max` are integers.
- `players_min <= players_max` and `time_min <= time_max`.
- Values exactly match the Task 3 matrix.
- The 17 imported records have the canonical Xiaohongshu URL in `链接`.
- The 17 imported descriptions contain neither `【内部来源】` nor `6991eec0000000001a02110c` nor a trailing literal `\\n`.
- `真真假假` has no fabricated link.
- The 8 date-only placeholders still have empty metadata cells.

Expected: zero violations in every category.

- [ ] **Step 3: Validate view isolation**

Read `+view-get-visible-fields` for all four views.

Expected: `所有反馈` matches the approved 13-field order; the other three views retain their pre-execution order.

- [ ] **Step 4: Report the completed migration**

Report: one reordered view, 17 migrated links, 18 completed player ranges, 18 completed time ranges, zero modified placeholders, and zero validation failures.
