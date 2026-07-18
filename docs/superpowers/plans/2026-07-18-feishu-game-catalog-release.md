# Feishu Game Catalog Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reviewed, versioned pipeline that turns user-supplied web game sources into Feishu Base drafts, exports only user-approved games into the iOS bundle, publishes authorized images to Cloudflare R2, and preserves a reproducible release audit trail.

**Architecture:** A focused TypeScript CLI owns Base schema inspection, draft upsert, release validation, deterministic catalog generation, image processing, and release reports. A small Cloudflare Worker serves immutable R2 image objects. The iOS app treats the bundled versioned catalog as the only official game list and downloads catalog-referenced images into a two-level cache; it never reads Feishu at runtime.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Package Manager, XCTest, TypeScript 5.7, Node.js 22, Vitest 4, Sharp, `lark-cli`, Cloudflare Workers, Wrangler 4, R2.

## Global Constraints

- New games and game text appear only in a new App build; no runtime catalog hot update.
- Feishu is the collection and review workspace, never an App runtime dependency.
- Only the user may set a record to `审核通过`.
- Source URLs stay internal to Feishu and are never emitted into the App catalog.
- Source-page images are never copied; only owned, licensed, or AI-generated attachments may publish.
- A release requires an explicit batch ID and an explicit user release instruction.
- Missing records are never interpreted as deletion; downline requires explicit `已下线` state.
- Images are immutable, content-hashed R2 objects and are loaded on demand by the App.
- External Base mutations, R2 uploads, Worker deployment, and release-state writeback require a user-confirmed execution checkpoint.
- Preserve unrelated changes in the existing dirty worktree; stage and commit only files named by the active task.

---

## Planned File Structure

### Game catalog tooling

- `tools/game-catalog/package.json` — scripts and pinned tool dependencies.
- `tools/game-catalog/tsconfig.json` — strict Node ESM compilation.
- `tools/game-catalog/src/domain.ts` — shared Base, draft, catalog, image, and report types.
- `tools/game-catalog/src/catalog-validation.ts` — pure normalization and release-blocking validation.
- `tools/game-catalog/src/lark-runner.ts` — typed subprocess boundary for `lark-cli`.
- `tools/game-catalog/src/base-client.ts` — Base field, view, record, and attachment operations.
- `tools/game-catalog/src/base-schema.ts` — exact desired fields, state options, and review views.
- `tools/game-catalog/src/schema-cli.ts` — inspect/plan/apply/verify schema migration.
- `tools/game-catalog/src/ingest.ts` — deterministic draft normalization and duplicate decisions.
- `tools/game-catalog/src/ingest-cli.ts` — NDJSON stdin preview/apply command.
- `tools/game-catalog/src/catalog-builder.ts` — approved-record mapping, deterministic ordering, and diff.
- `tools/game-catalog/src/image-publisher.ts` — attachment download, image validation, derivative creation, hashing, and R2 upload.
- `tools/game-catalog/src/release-runner.ts` — snapshot, validate, preview, publish, generate, verify, and report orchestration.
- `tools/game-catalog/src/release-cli.ts` — explicit batch release entry point.
- `tools/game-catalog/src/report.ts` — stable Markdown/JSON reports.
- `tools/game-catalog/test/*.test.ts` — pure and fake-runner regression coverage.
- `tools/game-catalog/test/fixtures/*` — approved, invalid, duplicate, and legacy catalog fixtures.

### R2 asset delivery

- `cloudflare/game-assets-worker/package.json` — Worker scripts and dependencies.
- `cloudflare/game-assets-worker/tsconfig.json` — Worker TypeScript config.
- `cloudflare/game-assets-worker/wrangler.jsonc` — `party-games-catalog-assets` R2 binding.
- `cloudflare/game-assets-worker/src/index.ts` — read-only immutable image endpoint.
- `cloudflare/game-assets-worker/src/index.test.ts` — R2 hit/miss, method, and cache-header tests.

### iOS catalog and images

- `PartyGames/Models/GameCatalog.swift` — versioned catalog envelope and compatibility validation.
- `PartyGames/Models/Game.swift` — CDN image URLs and expanded game-type mapping.
- `PartyGames/Models/GameEnums.swift` — light-prop and poker categories.
- `PartyGames/Services/GameStore.swift` — bundled catalog source of truth and legacy cache migration.
- `PartyGames/Services/RemoteGameImageStore.swift` — safe network/disk byte cache.
- `PartyGames/Services/AssetStore.swift` — image downsampling and remote/bundled fallback.
- `PartyGames/ViewModels/HomeViewModel.swift` — variant-aware image requests and bounded prefetch.
- `PartyGames/Views/HomeCardStackView.swift` — homepage image variant.
- `PartyGames/Views/LibraryGridView.swift` — homepage image variant.
- `PartyGames/Views/GameDetailView.swift` — detail image variant.
- `PartyGames/Views/MyPanelSheet.swift` — homepage image variant for existing preview.
- `PartyGames/Resources/game_catalog.json` — generated versioned catalog replacing the unversioned release role of `default_games.json`.
- `PartyGames.xcodeproj/project.pbxproj` — adds a real iOS unit-test target for UIKit-dependent package code.
- `PartyGames.xcodeproj/xcshareddata/xcschemes/PartyGamesiOS.xcscheme` — enables that target in the shared test action.
- `Tests/PartyGamesAppTests/URLProtocolStub.swift` — simulator-compatible request stub for App tests.
- `Tests/PartyGamesAppTests/GameCatalogTests.swift` — envelope decoding, validation, and legacy migration.
- `Tests/PartyGamesAppTests/RemoteGameImageStoreTests.swift` — HTTPS, cache, response, size, and retry behavior.

### Operational documentation

- `docs/operations/game-catalog-feishu.md` — field/view ownership and ingestion command.
- `docs/operations/game-catalog-release.md` — release, failure recovery, and rollback runbook.
- `docs/qa/game-catalog-release-matrix.md` — end-to-end acceptance matrix.

---

### Task 1: Establish the catalog domain and deterministic validator

**Files:**
- Create: `tools/game-catalog/package.json`
- Create: `tools/game-catalog/tsconfig.json`
- Create: `tools/game-catalog/src/domain.ts`
- Create: `tools/game-catalog/src/catalog-validation.ts`
- Create: `tools/game-catalog/test/catalog-validation.test.ts`
- Create: `tools/game-catalog/test/fixtures/approved-records.json`
- Create: `tools/game-catalog/test/fixtures/invalid-records.json`

**Interfaces:**
- Consumes: raw Base field maps and normalized source drafts.
- Produces: `normalizeLines(text: string): string[]`, `validatePublishableGame(record: BaseGameRecord): ValidationResult<CatalogGame>`, `stableContentHash(value: unknown): string`, and the canonical `CatalogGame`/`GameCatalogEnvelope` TypeScript shapes.

- [ ] **Step 1: Create the package and strict test setup**

```json
{
  "name": "party-games-catalog-tool",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc --noEmit",
    "schema": "tsx src/schema-cli.ts",
    "ingest": "tsx src/ingest-cli.ts",
    "release": "tsx src/release-cli.ts"
  },
  "dependencies": {
    "sharp": "^0.34.5"
  },
  "devDependencies": {
    "@types/node": "^22.15.0",
    "tsx": "^4.20.0",
    "typescript": "^5.7.2",
    "vitest": "^4.1.10"
  }
}
```

Create `tsconfig.json` with `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `module: NodeNext`, `moduleResolution: NodeNext`, and `target: ES2022`.

- [ ] **Step 2: Write failing tests for normalization and all release blockers**

```ts
import { describe, expect, it } from "vitest";
import { normalizeLines, validatePublishableGame } from "../src/catalog-validation.js";
import approved from "./fixtures/approved-records.json" with { type: "json" };
import invalid from "./fixtures/invalid-records.json" with { type: "json" };

describe("catalog validation", () => {
  it("normalizes one-item-per-line text deterministically", () => {
    expect(normalizeLines("  第一步\r\n\r\n第二步  \n")).toEqual(["第一步", "第二步"]);
  });

  it("maps a complete approved Base record", () => {
    const result = validatePublishableGame(approved[0]);
    expect(result.errors).toEqual([]);
    expect(result.value?.id).toBe("true_or_false");
    expect(result.value?.rules).toHaveLength(3);
  });

  it.each(invalid)("blocks $case", ({ record, expectedCode }) => {
    const result = validatePublishableGame(record);
    expect(result.errors.map(error => error.code)).toContain(expectedCode);
  });
});
```

The invalid fixture must include exact cases for missing ID, invalid slug, duplicate-ready empty name, player range reversal, time range reversal, empty rules, empty voice script, unsupported state, unsupported tool mapping, missing image, and `asset_rights=待确认`.

- [ ] **Step 3: Run the focused test and verify red**

Run: `cd tools/game-catalog && npm install && npm test -- catalog-validation.test.ts`

Expected: FAIL because `catalog-validation.ts` does not exist.

- [ ] **Step 4: Implement the canonical types and minimal validator**

```ts
export type WorkflowState = "草稿" | "待审核" | "审核驳回" | "审核通过" | "已打包" | "已上线" | "已下线";
export type AssetRights = "自有" | "已授权" | "AI生成" | "待确认";
export type CatalogGameType = "No Props" | "Light Props" | "Drinking" | "Dice" | "Cards";

export interface BaseAttachment {
  file_token: string;
  name: string;
  size: number;
}

export interface ValidationIssue {
  code: string;
  field: string;
  message: string;
}

export interface ValidationResult<T> {
  value?: T;
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
}

export interface BaseGameRecord {
  recordId: string;
  game_id?: string;
  name?: string;
  source_url?: string;
  players_min?: number;
  players_max?: number;
  time_min?: number;
  time_max?: number;
  emotion?: string[];
  tool?: string[];
  tags?: string[];
  description?: string;
  badge?: string;
  detail_intro?: string;
  rules?: string;
  preparation?: string;
  voice_script?: string;
  start_button_label?: string;
  sort_priority?: number;
  icon_homepage?: BaseAttachment[];
  icon_detailpage?: BaseAttachment[];
  asset_rights?: AssetRights;
  state?: WorkflowState;
  release_batch?: string;
  minimum_app_version?: string;
}

export interface CatalogGame {
  id: string;
  name: string;
  players: "2" | "3-4" | "5+";
  playerMin: number;
  playerMax: number;
  type: CatalogGameType;
  tags: string[];
  rules: string[];
  voiceScript: string[];
  cardDescription?: string;
  badge?: string;
  duration: string;
  detailIntro?: string;
  preparation?: string[];
  startButtonLabel?: string;
  homeImageURL: string;
  detailImageURL: string;
}

export interface GameCatalogEnvelope {
  schemaVersion: 2;
  catalogVersion: string;
  generatedAt: string;
  games: CatalogGame[];
}

export interface PublishedImageURLs {
  homeURL: string;
  detailURL: string;
  homeSHA256: string;
  detailSHA256: string;
}
```

Implement `validatePublishableGame` as a pure function that never reads environment variables, Base, disk, or network. Return all errors in one pass rather than failing at the first field.

- [ ] **Step 5: Run tests and typecheck**

Run: `cd tools/game-catalog && npm test -- catalog-validation.test.ts && npm run typecheck`

Expected: all validator tests PASS and TypeScript exits 0.

- [ ] **Step 6: Commit Task 1**

```bash
git add tools/game-catalog
git commit -m "feat: define validated game catalog domain"
```

---

### Task 2: Build a safe Feishu Base schema planner and verifier

**Files:**
- Create: `tools/game-catalog/src/lark-runner.ts`
- Create: `tools/game-catalog/src/base-client.ts`
- Create: `tools/game-catalog/src/base-schema.ts`
- Create: `tools/game-catalog/src/schema-cli.ts`
- Create: `tools/game-catalog/test/base-schema.test.ts`
- Create: `tools/game-catalog/test/base-client.test.ts`

**Interfaces:**
- Consumes: `LarkRunner.run(args: readonly string[], stdin?: string): Promise<unknown>` and current Base `field-list`/`view-list` responses.
- Produces: `planBaseMigration(snapshot: BaseSnapshot): MigrationPlan`, `applyBaseMigration(plan: MigrationPlan, client: BaseClient): Promise<void>`, and `verifyBaseSchema(snapshot: BaseSnapshot): SchemaVerification`.

- [ ] **Step 1: Write fake-runner tests for subprocess safety and read parsing**

```ts
it("never invokes lark-cli through a shell", async () => {
  const process = new FakeProcessAdapter();
  const runner = new LarkRunner(process);
  await runner.run(["base", "+field-list", "--as", "user", "--base-token", "token", "--table-id", "table"]);
  expect(process.lastSpawn?.shell).toBe(false);
});

it("maps matrix record-list output by returned field names", () => {
  const records = decodeRecordList(recordListFixture);
  expect(records[0]?.game_id).toBe("true_or_false");
  expect(records[0]?.recordId).toBe("rectgkBKRY");
});
```

- [ ] **Step 2: Write failing migration-plan tests**

The test must assert that the plan:

- preserves the current attachment fields;
- adds every field named in the approved design;
- expands `state` without allowing the migration tool to set `审核通过`;
- replaces the text `time_max` through a numeric shadow-field migration rather than destructive in-place conversion;
- creates eight review views with exact state filters;
- is empty when run against an already compliant snapshot.

```ts
expect(plan.operations).toContainEqual({
  kind: "createField",
  field: { type: "text", name: "game_id", description: "发布后不可修改的稳定英文标识" }
});
expect(plan.views.find(view => view.name === "待用户审核")?.filter).toEqual({
  logic: "and",
  conditions: [["state", "intersects", ["待审核"]]]
});
```

- [ ] **Step 3: Run the focused tests and verify red**

Run: `cd tools/game-catalog && npm test -- base-client.test.ts base-schema.test.ts`

Expected: FAIL because the runner, client, schema manifest, and planner do not exist.

- [ ] **Step 4: Implement the shell-free runner and Base client**

Use `spawnFile("lark-cli", args, { shell: false })`. Parse stdout as JSON and keep stderr separate. Provide exact methods:

```ts
interface BaseField { id: string; name: string; type: string; multiple?: boolean; options?: Array<{ name: string }> }
interface BaseView { id: string; name: string; type: string }
interface BaseFieldDefinition { type: string; name: string; [key: string]: unknown }
interface ViewFilter { logic: "and" | "or"; conditions: Array<readonly unknown[]> }
interface ReviewViewDefinition { name: string; type: "grid" | "kanban"; filter: ViewFilter }
interface RecordQuery { state?: WorkflowState; releaseBatch?: string; offset: number; limit: number }
interface BaseGameRecordPage { records: BaseGameRecord[]; hasMore: boolean; nextOffset?: number }
interface BaseSnapshot { fields: BaseField[]; views: BaseView[]; records: BaseGameRecord[] }
type MigrationOperation =
  | { kind: "createField"; field: BaseFieldDefinition }
  | { kind: "updateField"; fieldId: string; field: BaseFieldDefinition }
  | { kind: "migrateTimeMax"; legacyFieldId: string }
  | { kind: "createView"; view: ReviewViewDefinition }
  | { kind: "setViewFilter"; viewId: string; filter: ViewFilter };
interface MigrationPlan { operations: MigrationOperation[]; warnings: ValidationIssue[] }
interface SchemaVerification { ok: boolean; errors: ValidationIssue[] }

interface BaseClient {
  listFields(): Promise<BaseField[]>;
  listViews(): Promise<BaseView[]>;
  listRecords(query: RecordQuery): Promise<BaseGameRecordPage>;
  searchRecordsByGameId(gameId: string): Promise<BaseGameRecord[]>;
  createField(field: BaseFieldDefinition): Promise<void>;
  updateField(fieldId: string, field: BaseFieldDefinition, confirmed: boolean): Promise<void>;
  createView(view: ReviewViewDefinition): Promise<string>;
  setViewFilter(viewId: string, filter: ViewFilter): Promise<void>;
  upsertRecord(recordId: string | undefined, fields: Record<string, unknown>): Promise<string>;
  downloadAttachment(recordId: string, fileToken: string, outputDir: string): Promise<string>;
}
```

All mutating methods reject unless the caller passes the explicit confirmation token owned by the top-level CLI.

- [ ] **Step 5: Implement the exact schema manifest and idempotent planner**

The manifest must use Base-native definitions:

```ts
export const workflowStates = ["草稿", "待审核", "审核驳回", "审核通过", "已打包", "已上线", "已下线"] as const;

export const desiredFields: BaseFieldDefinition[] = [
  { type: "text", name: "game_id" },
  { type: "text", name: "source_url", style: { type: "url" } },
  { type: "text", name: "source_title" },
  { type: "datetime", name: "source_checked_at", style: { format: "yyyy-MM-dd HH:mm" } },
  { type: "text", name: "content_hash" },
  { type: "number", name: "time_max", style: { type: "plain", precision: 0, percentage: false, thousands_separator: false } },
  { type: "select", name: "tags", multiple: true, options: canonicalTagOptions },
  { type: "text", name: "badge" },
  { type: "text", name: "detail_intro" },
  { type: "text", name: "rules" },
  { type: "text", name: "preparation" },
  { type: "text", name: "voice_script" },
  { type: "text", name: "start_button_label" },
  { type: "number", name: "sort_priority", style: integerStyle },
  { type: "select", name: "asset_rights", multiple: false, options: assetRightsOptions },
  { type: "number", name: "image_focal_x", style: decimalStyle },
  { type: "number", name: "image_focal_y", style: decimalStyle },
  { type: "text", name: "image_home_url", style: { type: "url" } },
  { type: "text", name: "image_detail_url", style: { type: "url" } },
  { type: "text", name: "review_comment" },
  { type: "user", name: "reviewed_by", multiple: false },
  { type: "datetime", name: "reviewed_at", style: { format: "yyyy-MM-dd HH:mm" } },
  { type: "text", name: "release_batch" },
  { type: "text", name: "catalog_version" },
  { type: "text", name: "minimum_app_version" },
  { type: "datetime", name: "packed_at", style: { format: "yyyy-MM-dd HH:mm" } },
  { type: "text", name: "released_app_version" }
];
```

The canonical manifest names the final numeric field `time_max`. When the planner sees an existing text field with that name, it emits a separate confirmed shadow migration instead of also emitting the normal create operation: create transient numeric `time_max_v2`, parse every non-empty legacy value as an integer, write and verify every migrated record, rename old `time_max` to `time_max_legacy`, then rename `time_max_v2` to `time_max`. Never delete `time_max_legacy` in this project. A fresh plan against the final schema must produce no `time_max_v2` operation.

- [ ] **Step 6: Add preview/apply/verify CLI gates**

Commands:

```bash
npm run schema -- plan
npm run schema -- apply --confirm-base-mutation
npm run schema -- verify
```

`plan` and `verify` are read-only. `apply` exits 2 without `--confirm-base-mutation`, prints the target Base/table and operation count, executes serially, then performs a fresh field/view/record readback. It must not silently add `--yes` after a CLI confirmation error.

- [ ] **Step 7: Run tests and typecheck**

Run: `cd tools/game-catalog && npm test -- base-client.test.ts base-schema.test.ts && npm run typecheck`

Expected: PASS; the already-compliant fixture produces zero operations.

- [ ] **Step 8: Produce a real read-only migration preview**

Run with environment values supplied outside the repository:

```bash
cd tools/game-catalog
PARTY_GAMES_BASE_TOKEN="$PARTY_GAMES_BASE_TOKEN" PARTY_GAMES_TABLE_ID="$PARTY_GAMES_TABLE_ID" npm run schema -- plan
```

Expected: a JSON and Markdown plan naming the real “游戏汇总” table, with no Base writes.

- [ ] **Step 9: Stop for external-write confirmation before schema apply**

Show the real operation list, field migrations, view creations, record values affected by `time_max`, and required Base write scopes. Do not run `apply` until the user explicitly approves this exact migration.

- [ ] **Step 10: After confirmation, apply and verify online**

Run `apply --confirm-base-mutation`, then `verify`. Expected: all desired fields and eight views exist, every legacy record is preserved, and no record was moved to `审核通过`.

- [ ] **Step 11: Commit Task 2**

```bash
git add tools/game-catalog/src/lark-runner.ts tools/game-catalog/src/base-client.ts tools/game-catalog/src/base-schema.ts tools/game-catalog/src/schema-cli.ts tools/game-catalog/test/base-client.test.ts tools/game-catalog/test/base-schema.test.ts
git commit -m "feat: plan and verify game Base schema"
```

---

### Task 3: Add reviewed web-source draft ingestion

**Files:**
- Create: `tools/game-catalog/src/ingest.ts`
- Create: `tools/game-catalog/src/ingest-cli.ts`
- Create: `tools/game-catalog/test/ingest.test.ts`
- Create: `tools/game-catalog/test/fixtures/drafts.ndjson`
- Create: `docs/operations/game-catalog-feishu.md`

**Interfaces:**
- Consumes: newline-delimited `SourceGameDraft`, `BaseClient.searchRecordsByGameId`, and `BaseClient.upsertRecord`.
- Produces: `planDraftIngestion(drafts, existing): IngestionPlan` and `applyDraftIngestion(plan, client): Promise<IngestionReport>`.

- [ ] **Step 1: Write failing ingestion-policy tests**

```ts
it("never copies source image fields or approves a draft", () => {
  const plan = planDraftIngestion([sourceDraft], []);
  expect(plan.creates[0]?.fields.state).toBe("待审核");
  expect(plan.creates[0]?.fields).not.toHaveProperty("icon_homepage");
  expect(plan.creates[0]?.fields).not.toHaveProperty("icon_detailpage");
});

it("reports a same-name different-content conflict without overwriting", () => {
  const plan = planDraftIngestion([changedDraft], [existingApprovedRecord]);
  expect(plan.conflicts).toHaveLength(1);
  expect(plan.updates).toEqual([]);
});

it("does not downgrade an existing approved record", () => {
  const plan = planDraftIngestion([sameDraft], [existingApprovedRecord]);
  expect(plan.updates[0]?.fields).not.toHaveProperty("state");
});
```

- [ ] **Step 2: Run the focused test and verify red**

Run: `cd tools/game-catalog && npm test -- ingest.test.ts`

Expected: FAIL because ingestion functions do not exist.

- [ ] **Step 3: Implement source draft normalization and duplicate policy**

```ts
export interface SourceGameDraft {
  sourceUrl: string;
  sourceTitle: string;
  name: string;
  playerMin?: number;
  playerMax?: number;
  timeMin?: number;
  timeMax?: number;
  emotions: string[];
  tools: string[];
  tags: string[];
  description?: string;
  detailIntro?: string;
  rules: string[];
  preparation: string[];
  voiceScript: string[];
}
```

Normalize URL tracking parameters away, derive a slug candidate, calculate `content_hash`, and compare canonical URL, game ID, normalized name, then content hash. New drafts write `state=待审核`. Updates preserve the existing state and never set `审核通过`, `已打包`, `已上线`, or `已下线`.

- [ ] **Step 4: Implement preview-first NDJSON CLI**

```bash
cat /private/tmp/game-drafts.ndjson | npm run ingest -- preview
cat /private/tmp/game-drafts.ndjson | npm run ingest -- apply --confirm-base-mutation
```

The CLI reads stdin only, refuses image URL keys, validates every logical record before any write, prints expected create/update/conflict counts, applies writes serially, then rereads every returned record ID and asserts the final count. Partial failures produce a machine-readable failed-record list.

- [ ] **Step 5: Document the future agent workflow**

The runbook must state:

1. browse only user-supplied URLs;
2. rewrite into the project voice while preserving gameplay meaning;
3. retain `source_url` only in Base;
4. leave unverifiable facts empty;
5. never populate attachment fields from the source page;
6. show preview and conflict report;
7. apply only after the user asked to write those sources into Feishu;
8. reread and report record IDs and final states.

- [ ] **Step 6: Run tests and typecheck**

Run: `cd tools/game-catalog && npm test -- ingest.test.ts && npm run typecheck`

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add tools/game-catalog/src/ingest.ts tools/game-catalog/src/ingest-cli.ts tools/game-catalog/test/ingest.test.ts tools/game-catalog/test/fixtures/drafts.ndjson docs/operations/game-catalog-feishu.md
git commit -m "feat: add reviewed game draft ingestion"
```

---

### Task 4: Generate deterministic approved catalogs and release diffs

**Files:**
- Create: `tools/game-catalog/src/catalog-builder.ts`
- Create: `tools/game-catalog/src/report.ts`
- Create: `tools/game-catalog/test/catalog-builder.test.ts`
- Create: `tools/game-catalog/test/fixtures/previous-catalog.json`
- Create: `tools/game-catalog/test/fixtures/release-records.json`

**Interfaces:**
- Consumes: complete paginated `BaseGameRecord[]`, an existing `GameCatalogEnvelope`, and validated CDN URLs.
- Produces: `buildCatalog(input: CatalogBuildInput): CatalogBuildResult`, `diffCatalog(previous, next): CatalogDiff`, and `renderReleasePreview(result): string`.

- [ ] **Step 1: Write failing catalog and diff tests**

```ts
it("orders by priority then stable id and strips internal fields", () => {
  const result = buildCatalog(buildInput);
  expect(result.catalog.games.map(game => game.id)).toEqual(["alpha", "beta"]);
  expect(JSON.stringify(result.catalog)).not.toContain("source_url");
  expect(JSON.stringify(result.catalog)).not.toContain("review_comment");
});

it("does not interpret an absent old game as deletion", () => {
  const diff = diffCatalog(previousCatalog, nextCatalog);
  expect(diff.removals).toEqual([]);
  expect(diff.warnings.map(item => item.code)).toContain("MISSING_IS_NOT_DELETE");
});

it("produces byte-identical JSON for identical logical input", () => {
  expect(buildCatalog(buildInput).serialized).toBe(buildCatalog(shuffledInput).serialized);
});
```

- [ ] **Step 2: Run the focused test and verify red**

Run: `cd tools/game-catalog && npm test -- catalog-builder.test.ts`

Expected: FAIL because catalog build and report functions do not exist.

- [ ] **Step 3: Implement deterministic mapping**

Define and use these exact build-boundary types:

```ts
interface CatalogBuildInput {
  records: BaseGameRecord[];
  previousCatalog: GameCatalogEnvelope;
  catalogVersion: string;
  generatedAt: string;
  imageURLsByGameID: ReadonlyMap<string, PublishedImageURLs>;
  explicitDownlineIDs: ReadonlySet<string>;
}

interface CatalogDiff {
  additions: string[];
  modifications: Array<{ gameID: string; fields: string[] }>;
  removals: string[];
  unchanged: string[];
  warnings: ValidationIssue[];
}

interface CatalogBuildResult {
  catalog: GameCatalogEnvelope;
  serialized: string;
  diff: CatalogDiff;
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
}
```

Use `schemaVersion: 2`, require a caller-supplied `catalogVersion` and ISO `generatedAt`, sort all set-like arrays, sort games by `sort_priority` then `game_id`, and serialize with two-space indentation plus one trailing newline. Derive the legacy `players` bucket from min/max only for UI compatibility; min/max remain authoritative.

- [ ] **Step 4: Implement explicit diff semantics**

Classify additions, field-level modifications, explicit downlines, unchanged entries, and warnings. A removal exists only when the Base record for that stable ID has `state=已下线`; an old ID absent from the selected batch remains in the next catalog unchanged.

- [ ] **Step 5: Render JSON and Markdown previews**

The Markdown report includes batch ID, catalog version, counts, every changed ID, field names changed, explicit downlines, blockers, warnings, and previous/next catalog SHA-256 values.

- [ ] **Step 6: Run tests and typecheck**

Run: `cd tools/game-catalog && npm test -- catalog-builder.test.ts && npm run typecheck`

Expected: PASS.

- [ ] **Step 7: Commit Task 4**

```bash
git add tools/game-catalog/src/catalog-builder.ts tools/game-catalog/src/report.ts tools/game-catalog/test/catalog-builder.test.ts tools/game-catalog/test/fixtures/previous-catalog.json tools/game-catalog/test/fixtures/release-records.json
git commit -m "feat: build deterministic reviewed catalogs"
```

---

### Task 5: Publish immutable authorized images and serve them from R2

**Files:**
- Create: `tools/game-catalog/src/image-publisher.ts`
- Create: `tools/game-catalog/test/image-publisher.test.ts`
- Create: `tools/game-catalog/test/fixtures/home-source.jpg`
- Create: `tools/game-catalog/test/fixtures/detail-source.jpg`
- Create: `cloudflare/game-assets-worker/package.json`
- Create: `cloudflare/game-assets-worker/tsconfig.json`
- Create: `cloudflare/game-assets-worker/wrangler.jsonc`
- Create: `cloudflare/game-assets-worker/src/index.ts`
- Create: `cloudflare/game-assets-worker/src/index.test.ts`

**Interfaces:**
- Consumes: confirmed Base attachments, `image_focal_x/y`, `PARTY_GAMES_ASSET_BASE_URL`, and a shell-free `R2Uploader`.
- Produces: `publishGameImages(input: ImagePublishInput): Promise<PublishedImageURLs>` and the public GET endpoint `/games/{gameID}/{sha256}-{variant}.jpg`.

- [ ] **Step 1: Write failing image pipeline tests**

Cover exact behaviors:

- reject `asset_rights=待确认` before download;
- reject unsupported MIME, corrupt bytes, a source over 20 MiB, and an image smaller than 600 px on its short edge;
- generate homepage and detail JPEG derivatives with EXIF orientation applied;
- include source/transform bytes in SHA-256;
- skip `wrangler r2 object put` when `head` reports an existing key;
- never use a URL or file name from the source website.

```ts
expect(result.homeURL).toMatch(/^https:\/\/assets\.party-games\.test\/games\/true_or_false\/[a-f0-9]{64}-home\.jpg$/);
expect(fakeUploader.putCalls).toHaveLength(2);
```

- [ ] **Step 2: Write failing Worker tests**

```ts
it("serves an existing immutable image", async () => {
  const response = await SELF.fetch("https://worker.test/games/true_or_false/hash-home.jpg");
  expect(response.status).toBe(200);
  expect(response.headers.get("Cache-Control")).toBe("public, max-age=31536000, immutable");
});

it.each(["POST", "PUT", "DELETE"])("rejects %s", async method => {
  expect((await SELF.fetch("https://worker.test/games/x/y.jpg", { method })).status).toBe(405);
});
```

- [ ] **Step 3: Run focused tests and verify red**

Run:

```bash
cd tools/game-catalog && npm test -- image-publisher.test.ts
cd ../../cloudflare/game-assets-worker && npm install && npm test
```

Expected: FAIL because the publisher and Worker do not exist.

- [ ] **Step 4: Implement image derivatives and shell-free R2 uploader**

Define the boundary without exposing Base download URLs:

```ts
interface ImagePublishInput {
  gameID: string;
  assetRights: AssetRights;
  homeSourcePath: string;
  detailSourcePath: string;
  focalX?: number;
  focalY?: number;
  assetBaseURL: string;
}

interface R2Uploader {
  exists(key: string): Promise<boolean>;
  put(key: string, relativeFilePath: string, contentType: "image/jpeg"): Promise<void>;
}
```

Use Sharp with exact output policies:

- homepage: max 1200 px long edge, JPEG quality 82;
- detail: max 1800 px long edge, JPEG quality 84;
- rotate from EXIF before resize;
- no upscaling;
- strip metadata;
- calculate the final derivative hash and key after encoding.

Invoke Wrangler as argument arrays with `shell: false`:

```ts
["r2", "object", "get", `party-games-catalog-assets/${key}`, "--pipe"]
["r2", "object", "put", `party-games-catalog-assets/${key}`, "--file", localRelativePath, "--content-type", "image/jpeg", "--cache-control", "public, max-age=31536000, immutable", "--remote"]
```

Treat an object-not-found result as upload-needed; do not retry authentication or quota errors unchanged.

- [ ] **Step 5: Implement the read-only asset Worker**

`wrangler.jsonc` uses worker name `party-games-catalog-assets`, compatibility date `2026-07-18`, and binding `ASSETS` to bucket `party-games-catalog-assets`. The Worker accepts only `GET`/`HEAD`, rejects path traversal and non-`games/` keys, returns 404 for misses, mirrors ETag/content type, and sets immutable cache headers.

- [ ] **Step 6: Run tests, typechecks, and local Worker smoke**

Run:

```bash
cd tools/game-catalog && npm test -- image-publisher.test.ts && npm run typecheck
cd ../../cloudflare/game-assets-worker && npm test && npm run typecheck
```

Expected: all PASS.

- [ ] **Step 7: Stop for Cloudflare resource confirmation**

Before `wrangler r2 bucket create`, Worker deployment, or remote uploads, show the exact account, bucket name, Worker name, expected public URL, and that game images are publicly readable. Execute only after explicit user confirmation.

- [ ] **Step 8: After confirmation, create/deploy and smoke-test**

Create bucket `party-games-catalog-assets`, deploy Worker `party-games-catalog-assets`, upload only the two test derivatives, then verify GET, HEAD, 404, method rejection, content type, and immutable caching from the real HTTPS URL. Remove test objects only with separate explicit confirmation; otherwise retain them under `games/__smoke__/` for future health checks.

- [ ] **Step 9: Commit Task 5**

```bash
git add tools/game-catalog/src/image-publisher.ts tools/game-catalog/test/image-publisher.test.ts tools/game-catalog/test/fixtures cloudflare/game-assets-worker
git commit -m "feat: publish immutable game images"
```

---

### Task 6: Orchestrate atomic release preparation and reporting

**Files:**
- Create: `tools/game-catalog/src/release-runner.ts`
- Create: `tools/game-catalog/src/release-cli.ts`
- Create: `tools/game-catalog/test/release-runner.test.ts`
- Create: `docs/operations/game-catalog-release.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `BaseClient`, `buildCatalog`, `publishGameImages`, the previous bundled catalog, explicit batch/catalog/App versions, and environment configuration.
- Produces: `prepareRelease(request: ReleaseRequest): Promise<ReleasePreview>` and `executeRelease(preview, confirmation): Promise<ReleaseResult>`.

- [ ] **Step 1: Write failing orchestration tests**

```ts
it("reads every page and asserts expected record count", async () => {
  const result = await prepareRelease(request, depsWithTwoPages);
  expect(result.inputCount).toBe(201);
  expect(deps.base.listPageCalls).toEqual([0, 200]);
});

it("performs no writes when any blocker exists", async () => {
  await expect(executeRelease(blockedPreview, confirmation, deps)).rejects.toThrow("release blocked");
  expect(deps.r2.putCalls).toEqual([]);
  expect(deps.files.writeCalls).toEqual([]);
  expect(deps.base.updateCalls).toEqual([]);
});

it("writes the catalog atomically only after all image uploads pass", async () => {
  await executeRelease(validPreview, confirmation, deps);
  expect(deps.events).toEqual(["snapshot", "images", "temp-catalog", "verify", "atomic-rename", "report"]);
});
```

- [ ] **Step 2: Run the focused test and verify red**

Run: `cd tools/game-catalog && npm test -- release-runner.test.ts`

Expected: FAIL because release orchestration does not exist.

- [ ] **Step 3: Implement read-only prepare phase**

Define the orchestration state explicitly:

```ts
interface ReleaseRequest {
  batch: string;
  catalogVersion: string;
  appVersion: string;
}

interface ReleasePreview {
  request: ReleaseRequest;
  inputCount: number;
  inputSHA256: string;
  build: CatalogBuildResult;
  workDirectory: string;
}

interface ReleaseConfirmation {
  confirmed: true;
  expectedInputSHA256: string;
}

interface ReleaseResult {
  catalogPath: string;
  catalogSHA256: string;
  reportPath: string;
  publishedImages: ReadonlyMap<string, PublishedImageURLs>;
}
```

`prepareRelease` requires non-empty exact strings for batch, catalog version, and App version. It queries all `审核通过` records in the batch with pages of 200, separately queries explicit `已下线` records in the same batch, snapshots normalized input under `.release-work/2026-08-01/input.json` for the example batch, validates every record, computes the diff, and writes preview reports. It performs no R2, Base, or official catalog writes.

- [ ] **Step 4: Implement confirmed execute phase**

The CLI requires:

```bash
npm run release -- prepare --batch 2026-08-01 --catalog-version 2026.08.01 --app-version 1.4.0
npm run release -- execute --batch 2026-08-01 --catalog-version 2026.08.01 --app-version 1.4.0 --confirm-release
```

`execute` rereads Base and rejects if the snapshot hash changed after preview. It uploads images first, constructs final URLs, writes `PartyGames/Resources/game_catalog.json.tmp`, invokes the catalog decoder verification command, atomically renames the file, and writes JSON/Markdown reports. It does not mark records `已打包` until all project tests/builds have succeeded in Task 9.

- [ ] **Step 5: Add release workspace ignores and rollback rules**

Add `.release-work/` to `.gitignore`. The runbook must state that generated input snapshots and temporary attachments remain local, reports are copied to `docs/qa/releases/2026-08-01.md` for the example batch only after success, and rollback restores the previous committed catalog. R2 hash objects are not deleted during rollback.

- [ ] **Step 6: Run tests and typecheck**

Run: `cd tools/game-catalog && npm test -- release-runner.test.ts && npm run typecheck`

Expected: PASS.

- [ ] **Step 7: Commit Task 6**

```bash
git add tools/game-catalog/src/release-runner.ts tools/game-catalog/src/release-cli.ts tools/game-catalog/test/release-runner.test.ts docs/operations/game-catalog-release.md .gitignore
git commit -m "feat: orchestrate reviewed catalog releases"
```

---

### Task 7: Make the bundled versioned catalog the iOS source of truth

**Files:**
- Create: `PartyGames/Models/GameCatalog.swift`
- Modify: `PartyGames/Models/Game.swift`
- Modify: `PartyGames/Models/GameEnums.swift`
- Modify: `PartyGames/Services/GameStore.swift`
- Create: `PartyGames/Resources/game_catalog.json`
- Modify: `PartyGames.xcodeproj/project.pbxproj`
- Modify: `PartyGames.xcodeproj/xcshareddata/xcschemes/PartyGamesiOS.xcscheme`
- Create: `Tests/PartyGamesAppTests/GameCatalogTests.swift`
- Modify: `Tests/run-regressions.sh`

**Interfaces:**
- Consumes: generated `game_catalog.json` with `schemaVersion=2`.
- Produces: `GameCatalogEnvelope`, `GameStore.loadCatalog(bundleData:defaults:) -> [Game]`, and a one-time legacy UserDefaults cleanup that preserves favorites/history stores.

- [ ] **Step 1: Add a real iOS unit-test target and shared test action**

Add target `PartyGamesAppTests` with product type `com.apple.product-type.bundle.unit-test`, iOS deployment target 26.0, generated Info.plist, and dependency/linkage on the local `PartyGames` package product. Add `Tests/PartyGamesAppTests` as its source group. Add `PartyGamesAppTests` to the `PartyGamesiOS` shared scheme `TestAction` while leaving the existing build and launch actions unchanged.

Run:

```bash
xcodebuild test -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Expected before adding catalog tests: the test action is available and exits 0. This replaces the currently invalid `swift test` path, which builds for macOS and cannot import UIKit.

- [ ] **Step 2: Write failing catalog decode and migration tests**

```swift
func testDecodesVersionedCatalog() throws {
    let catalog = try JSONDecoder().decode(GameCatalogEnvelope.self, from: fixtureData)
    XCTAssertEqual(catalog.schemaVersion, 2)
    XCTAssertEqual(catalog.games.first?.homeImageURL?.scheme, "https")
}

func testBundledCatalogWinsOverLegacyGameArray() throws {
    let defaults = try makeDefaults()
    defaults.set(legacyGameArrayData, forKey: "party-games")
    let games = try GameStore.loadCatalog(bundleData: fixtureData, defaults: defaults)
    XCTAssertEqual(games.map(\.id), ["catalog_game"])
    XCTAssertNil(defaults.data(forKey: "party-games"))
}

func testMigrationDoesNotClearFavoritesOrHistory() throws {
    let defaults = try makeDefaults()
    defaults.set(try JSONEncoder().encode(["catalog_game"]), forKey: "party-favorites")
    defaults.set(try JSONEncoder().encode(["catalog_game"]), forKey: "party-game-history")
    _ = try GameStore.loadCatalog(bundleData: fixtureData, defaults: defaults)
    XCTAssertNotNil(defaults.data(forKey: "party-favorites"))
    XCTAssertNotNil(defaults.data(forKey: "party-game-history"))
}
```

Inspect the real keys in `FavoritesStore` and `HistoryStore` and use those exact strings in the final test.

- [ ] **Step 3: Run the focused test and verify red**

Run:

```bash
xcodebuild test -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:PartyGamesAppTests/GameCatalogTests
```

Expected: FAIL because `GameCatalogEnvelope` and `loadCatalog` do not exist.

- [ ] **Step 4: Implement the envelope and model mapping**

```swift
struct GameCatalogEnvelope: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 2
    let schemaVersion: Int
    let catalogVersion: String
    let generatedAt: Date
    let games: [Game]

    func validated() throws -> Self {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw GameCatalogError.unsupportedSchema(schemaVersion)
        }
        guard Set(games.map(\.id)).count == games.count else {
            throw GameCatalogError.duplicateGameID
        }
        return self
    }
}
```

Add `homeImageURL` and `detailImageURL` optional URL properties to `Game`. Add exact `GameType` raw values `Light Props` and `Cards`. Keep old JSON compatibility by using optional image URLs and decoding the legacy raw values already present.

Configure the catalog `JSONDecoder` with `.iso8601` for `generatedAt`; do not rely on Foundation's default numeric date decoding.

- [ ] **Step 5: Replace full-array UserDefaults precedence**

`GameStore.load()` decodes and validates `game_catalog.json` first. On successful load, it removes only the legacy `party-games` full-array key. It does not clear favorites, history, notification decisions, Mahjong state, or unrelated defaults. Retain `default_games.json` only as a one-release emergency fallback; log fallback use in debug builds and remove its official-source role.

- [ ] **Step 6: Add a standalone generated-catalog decoder regression**

Extend `Tests/run-regressions.sh` to compile a small executable that reads `PartyGames/Resources/game_catalog.json`, decodes the envelope, validates schema, ID uniqueness, non-empty rules/voice script, HTTPS image URLs, and player/time ranges.

- [ ] **Step 7: Run tests and iOS build**

Run:

```bash
xcodebuild test -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:PartyGamesAppTests/GameCatalogTests
zsh Tests/run-regressions.sh
xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS and `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit Task 7**

```bash
git add PartyGames/Models/GameCatalog.swift PartyGames/Models/Game.swift PartyGames/Models/GameEnums.swift PartyGames/Services/GameStore.swift PartyGames/Resources/game_catalog.json PartyGames.xcodeproj/project.pbxproj PartyGames.xcodeproj/xcshareddata/xcschemes/PartyGamesiOS.xcscheme Tests/PartyGamesAppTests/GameCatalogTests.swift Tests/run-regressions.sh
git commit -m "feat: load versioned bundled game catalog"
```

---

### Task 8: Add variant-aware CDN image caching to iOS

**Files:**
- Create: `PartyGames/Services/RemoteGameImageStore.swift`
- Modify: `PartyGames/Services/AssetStore.swift`
- Modify: `PartyGames/ViewModels/HomeViewModel.swift`
- Modify: `PartyGames/Views/HomeCardStackView.swift`
- Modify: `PartyGames/Views/LibraryGridView.swift`
- Modify: `PartyGames/Views/GameDetailView.swift`
- Modify: `PartyGames/Views/MyPanelSheet.swift`
- Create: `Tests/PartyGamesAppTests/URLProtocolStub.swift`
- Create: `Tests/PartyGamesAppTests/RemoteGameImageStoreTests.swift`

**Interfaces:**
- Consumes: `Game.homeImageURL`, `Game.detailImageURL`, `URLSession`, and a cache directory.
- Produces: `RemoteGameImageStore.data(for:) async -> Data?`, `AssetStore.loadImage(for:variant:) async -> UIImage?`, and `HomeViewModel.gameImage(for:variant:)`.

- [ ] **Step 1: Write failing remote-store tests with `URLProtocolStub`**

Cover:

- HTTPS-only URL acceptance;
- memory-equivalent second request is served from disk without network;
- non-200, non-image MIME, empty data, over-20-MiB response, and decode failure are rejected;
- failed temporary download never leaves a final cache file;
- a corrupt existing cache entry is removed and refetched once;
- cancellation does not retry;
- HTTP 5xx retries at most twice with injectable zero-delay test clock.

```swift
func testSecondLoadUsesDiskCache() async throws {
    let first = await store.data(for: imageURL)
    let second = await store.data(for: imageURL)
    XCTAssertEqual(first, imageData)
    XCTAssertEqual(second, imageData)
    XCTAssertEqual(URLProtocolStub.requestCount, 1)
}
```

- [ ] **Step 2: Run the focused test and verify red**

Run:

```bash
xcodebuild test -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:PartyGamesAppTests/RemoteGameImageStoreTests
```

Expected: FAIL because `RemoteGameImageStore` does not exist.

- [ ] **Step 3: Implement the safe byte cache**

Use an actor and inject `URLSession`, `FileManager`, cache root, maximum byte count, retry clock, and validator. Cache key is SHA-256 of the immutable URL string. Require HTTPS, HTTP 200, `image/jpeg` or `image/png`, and 1...20 MiB. Write `*.partial`, sync/close, then atomically move to the final hash path.

- [ ] **Step 4: Make `AssetStore` variant-aware**

```swift
enum GameImageVariant: String, Hashable, Sendable { case homepage, detail }

struct GameImageKey: Hashable, Sendable {
    let gameID: String
    let variant: GameImageVariant
}
```

Resolve the selected URL from the `Game`, fetch bytes through `RemoteGameImageStore`, downsample to 900 px for homepage and 1600 px for detail, and retain the current bundled image as a fallback for `true_or_false`. Return `nil` on failure so views keep their existing placeholder behavior.

- [ ] **Step 5: Update ViewModel prefetch without loading the full library**

Replace the single `[String: UIImage]` cache with `[GameImageKey: UIImage]`. Homepage deck prefetch remains bounded to the current card neighborhood. Library image requests are initiated for visible cards, not every filtered game at tab entry. Detail view requests the detail variant only when opened. Cancel superseded tasks.

- [ ] **Step 6: Update all image consumers**

- Home card, library card, and admin preview request `.homepage`.
- Game detail requests `.detail`, falling back to `.homepage` when the detail URL is absent.
- Existing layout, placeholders, and accessibility labels remain unchanged.

- [ ] **Step 7: Run focused and full iOS verification**

Run:

```bash
xcodebuild test -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:PartyGamesAppTests/RemoteGameImageStoreTests
xcodebuild test -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
zsh Tests/run-regressions.sh
xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS and `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit Task 8**

```bash
git add PartyGames/Services/RemoteGameImageStore.swift PartyGames/Services/AssetStore.swift PartyGames/ViewModels/HomeViewModel.swift PartyGames/Views/HomeCardStackView.swift PartyGames/Views/LibraryGridView.swift PartyGames/Views/GameDetailView.swift PartyGames/Views/MyPanelSheet.swift Tests/PartyGamesAppTests/URLProtocolStub.swift Tests/PartyGamesAppTests/RemoteGameImageStoreTests.swift
git commit -m "feat: cache catalog images from CDN"
```

---

### Task 9: Complete the end-to-end trial release and write back audit state

**Files:**
- Modify: `tools/game-catalog/src/release-runner.ts`
- Modify: `tools/game-catalog/src/release-cli.ts`
- Modify: `tools/game-catalog/test/release-runner.test.ts`
- Create: `docs/qa/game-catalog-release-matrix.md`
- Create: `docs/qa/releases/2026-08-01.md` during the trial release

**Interfaces:**
- Consumes: successful TypeScript tests, Worker tests, Swift tests, iOS build, real Base records, real R2/Worker endpoint, and explicit user confirmation.
- Produces: committed catalog, release report, `已打包` writeback, and a repeatable final verification command.

- [ ] **Step 1: Write failing post-build writeback tests**

```ts
it("writes 已打包 only after every verifier succeeds", async () => {
  await runPostBuild(validRelease, passingVerifiers, deps);
  expect(deps.base.updateCalls).toEqual([
    expect.objectContaining({ state: "已打包", catalog_version: "2026.08.01", released_app_version: "1.4.0" })
  ]);
});

it("leaves Base state unchanged when xcodebuild fails", async () => {
  await expect(runPostBuild(validRelease, failingBuild, deps)).rejects.toThrow();
  expect(deps.base.updateCalls).toEqual([]);
});
```

- [ ] **Step 2: Run the focused test and verify red**

Run: `cd tools/game-catalog && npm test -- release-runner.test.ts`

Expected: FAIL because post-build writeback is not implemented.

- [ ] **Step 3: Add exact verifier orchestration**

Run in this order, stop on first failure, and capture stdout/stderr separately:

```bash
cd tools/game-catalog && npm test && npm run typecheck
cd ../../cloudflare/game-assets-worker && npm test && npm run typecheck
cd ../.. && xcodebuild test -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
zsh Tests/run-regressions.sh
xcodebuild -project PartyGames.xcodeproj -scheme PartyGamesiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Only after all commands pass may the tool update released records to `已打包`, set `catalog_version`, `packed_at`, and the target `released_app_version`. It must not set `已上线`; that remains a later user-confirmed action after App Store release.

- [ ] **Step 4: Select a small real trial batch**

Use one to three user-approved games with owned/licensed/AI-generated image attachments. The user must explicitly mark them `审核通过`, assign batch `2026-08-01`, and authorize the trial release. Do not use the placeholder date-only records.

- [ ] **Step 5: Run prepare and review the real diff**

Run the prepare command, then verify record count, every game ID, source exclusion, image rights, additions/modifications/downlines, and catalog hash. Stop and ask for corrections if any blocker or unexpected change appears.

- [ ] **Step 6: Execute the confirmed trial release**

Run the execute command with `--confirm-release`, then run the exact verifier sequence. Confirm the R2 URLs return immutable images, the generated catalog decodes, and the simulator shows the expected home/library/detail images with the network disabled after cache warmup.

- [ ] **Step 7: Write and verify the audit report**

Create `docs/qa/releases/2026-08-01.md` containing the batch, catalog/App versions, Base record IDs, catalog hash, image object hashes, test commands/results, code commit, and rollback commit. Reread Base records and verify `已打包`; do not mark `已上线`.

- [ ] **Step 8: Complete the reusable QA matrix**

The matrix must include ingestion, duplicate conflict, user-only approval, pagination, validation blockers, diff semantics, R2 immutability, App upgrade migration, favorites/history preservation, first-load image behavior, warm-cache offline behavior, corrupted-cache recovery, and rollback.

- [ ] **Step 9: Run the full verification once more from a clean process**

Run the exact verifier sequence from Step 3. Expected: every command exits 0 and iOS reports `BUILD SUCCEEDED`.

- [ ] **Step 10: Commit Task 9**

```bash
git add PartyGames/Resources/game_catalog.json tools/game-catalog/src/release-runner.ts tools/game-catalog/src/release-cli.ts tools/game-catalog/test/release-runner.test.ts docs/qa/game-catalog-release-matrix.md docs/qa/releases/2026-08-01.md
git commit -m "feat: complete reviewed game catalog release"
```

---

## Final Acceptance Checklist

- [ ] A user-supplied web URL can be converted into one or more traceable Base drafts without copying source images.
- [ ] Draft ingestion cannot mark any record `审核通过`.
- [ ] Duplicate URL, ID, name, and content-hash conflicts are reported without destructive overwrite.
- [ ] Schema planning is idempotent and real Base mutations are separately confirmed and reread.
- [ ] Only the requested batch's complete, paginated `审核通过` records enter release preparation.
- [ ] Missing records do not delete existing games; only explicit `已下线` does.
- [ ] Internal source/review/Base fields never enter `game_catalog.json`.
- [ ] Identical logical input produces identical ordered catalog bytes and hashes.
- [ ] Unauthorized, missing, corrupt, undersized, oversized, or unsupported images block release.
- [ ] Published image keys are immutable SHA-256 objects, and the Worker is read-only.
- [ ] The App always uses the new bundled catalog after upgrade while preserving valid favorites/history.
- [ ] CDN failure never blocks game text, and warm cached images work offline.
- [ ] Base state advances to `已打包` only after all tests and the iOS build pass.
- [ ] Base state advances to `已上线` only after a later explicit user confirmation of App Store release.
- [ ] Every release has an input snapshot hash, catalog hash, image hashes, report, code commit, and rollback reference.
