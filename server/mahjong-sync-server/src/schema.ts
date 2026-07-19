import type Database from "better-sqlite3";

export function migrate(database: Database.Database): void {
  database.pragma("journal_mode = WAL");
  database.exec(`
    CREATE TABLE IF NOT EXISTS mahjong_rooms (
      id TEXT PRIMARY KEY,
      code TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      mode TEXT NOT NULL DEFAULT 'multiplayer',
      starting_score INTEGER NOT NULL DEFAULT 0,
      owner_device_id TEXT NOT NULL,
      multiplier REAL NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      ended_at TEXT,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS mahjong_room_members (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL REFERENCES mahjong_rooms(id) ON DELETE CASCADE,
      device_id TEXT NOT NULL,
      display_name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'player',
      joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(room_id, device_id)
    );

    CREATE TABLE IF NOT EXISTS mahjong_players (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL REFERENCES mahjong_rooms(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      device_id TEXT,
      seat TEXT,
      score INTEGER NOT NULL,
      multiplier_score REAL NOT NULL DEFAULT 0,
      result TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS mahjong_score_events (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL REFERENCES mahjong_rooms(id) ON DELETE CASCADE,
      player_id TEXT NOT NULL REFERENCES mahjong_players(id) ON DELETE CASCADE,
      actor_member_id TEXT NOT NULL REFERENCES mahjong_room_members(id),
      delta INTEGER NOT NULL,
      reason TEXT,
      score_after INTEGER NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_mahjong_rooms_code ON mahjong_rooms(code);
    CREATE INDEX IF NOT EXISTS idx_mahjong_room_members_device ON mahjong_room_members(device_id);
    CREATE INDEX IF NOT EXISTS idx_mahjong_players_room ON mahjong_players(room_id, sort_order);
    CREATE INDEX IF NOT EXISTS idx_mahjong_score_events_room ON mahjong_score_events(room_id, created_at);
  `);

  addColumn(database, "mahjong_rooms", "mode", "TEXT NOT NULL DEFAULT 'multiplayer'");
  addColumn(database, "mahjong_rooms", "multiplier", "REAL NOT NULL DEFAULT 1");
  addColumn(database, "mahjong_players", "device_id", "TEXT");
  addColumn(database, "mahjong_players", "multiplier_score", "REAL NOT NULL DEFAULT 0");
  addColumn(database, "mahjong_players", "result", "TEXT");
}

function addColumn(database: Database.Database, table: string, column: string, definition: string): void {
  const columns = database.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>;
  if (!columns.some((item) => item.name === column)) {
    database.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}
