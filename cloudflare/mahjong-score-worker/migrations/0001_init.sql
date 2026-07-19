CREATE TABLE IF NOT EXISTS mahjong_rooms (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  starting_score INTEGER NOT NULL DEFAULT 25000,
  owner_device_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS mahjong_room_members (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES mahjong_rooms(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'player',
  joined_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(room_id, device_id)
);

CREATE TABLE IF NOT EXISTS mahjong_players (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES mahjong_rooms(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  seat TEXT,
  score INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS mahjong_score_events (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES mahjong_rooms(id) ON DELETE CASCADE,
  player_id TEXT NOT NULL REFERENCES mahjong_players(id) ON DELETE CASCADE,
  actor_member_id TEXT NOT NULL REFERENCES mahjong_room_members(id),
  delta INTEGER NOT NULL,
  reason TEXT,
  score_after INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_mahjong_rooms_code ON mahjong_rooms(code);
CREATE INDEX IF NOT EXISTS idx_mahjong_room_members_device ON mahjong_room_members(device_id);
CREATE INDEX IF NOT EXISTS idx_mahjong_players_room ON mahjong_players(room_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_mahjong_score_events_room ON mahjong_score_events(room_id, created_at);
