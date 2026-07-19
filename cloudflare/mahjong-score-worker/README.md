# Mahjong Score Worker

Cloudflare backend for the Mahjong scorekeeper. It uses:

- Worker HTTP API for room creation, join, history, and snapshots.
- Durable Object per room for realtime WebSocket score changes.
- D1 for room, player, member, score event, and finished-room history storage.

## Local setup

Copy `.env.example` to `.env` and fill local values:

```sh
MEMBER_TOKEN_SECRET=...
```

For local development, use `npx wrangler login` instead of putting a Cloudflare API token in `.env`.

Install dependencies and run locally:

```sh
npm install
npm run db:migrate:local
npm run dev
```

## Deploy setup

Create the remote D1 database and replace `database_id` in `wrangler.jsonc`:

```sh
npx wrangler d1 create mahjong_score_db
```

Set Worker secrets:

```sh
npx wrangler secret put MEMBER_TOKEN_SECRET
```

Apply remote migrations and deploy:

```sh
npm run db:migrate:remote
npm run deploy
```

## API

`POST /rooms`

```json
{
  "deviceId": "ios-device-id",
  "displayName": "Alice",
  "title": "Friday Mahjong",
  "startingScore": 0,
  "players": [{ "name": "Alice", "seat": "east" }]
}
```

Returns `memberToken` and `snapshot`.

`POST /rooms/:code/join`

```json
{
  "deviceId": "ios-device-id-2",
  "displayName": "Bob"
}
```

Returns `memberToken` and `snapshot`.

`GET /rooms/:code`

Returns the latest room snapshot.

`GET /history?deviceId=ios-device-id`

Returns rooms joined by that device, including ended rooms.

`POST /rooms/:code/end`

Requires `Authorization: Bearer <memberToken>`.

`GET /rooms/:code/ws?memberToken=<memberToken>`

Realtime channel. Send:

```json
{
  "type": "adjust_score",
  "playerId": "player-id",
  "delta": 1000,
  "reason": "ron"
}
```

The server broadcasts:

```json
{
  "type": "state",
  "snapshot": {}
}
```
