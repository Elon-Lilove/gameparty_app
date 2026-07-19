ALTER TABLE mahjong_rooms ADD COLUMN mode TEXT NOT NULL DEFAULT 'multiplayer';
ALTER TABLE mahjong_rooms ADD COLUMN multiplier REAL NOT NULL DEFAULT 1;

ALTER TABLE mahjong_players ADD COLUMN device_id TEXT;
ALTER TABLE mahjong_players ADD COLUMN multiplier_score REAL NOT NULL DEFAULT 0;
ALTER TABLE mahjong_players ADD COLUMN result TEXT;
