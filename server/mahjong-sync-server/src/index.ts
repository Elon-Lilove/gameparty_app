import { createMahjongSyncServer } from "./server.js";

const port = Number(process.env.PORT ?? 8787);
const databasePath = process.env.DATABASE_PATH ?? "./data/mahjong.sqlite";
const memberTokenSecret = process.env.MEMBER_TOKEN_SECRET;

if (!memberTokenSecret) {
  throw new Error("MEMBER_TOKEN_SECRET is required");
}

const server = await createMahjongSyncServer({
  databasePath,
  memberTokenSecret,
  port,
});

console.log(`Mahjong sync server listening on ${server.url}`);
