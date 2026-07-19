# Mahjong Sync Server

Node.js WebSocket backend for the iOS Mahjong scorekeeper. It is compatible with the current app API:

- `POST /rooms`
- `POST /rooms/:code/join`
- `GET /rooms/:code`
- `GET /rooms/:code/ws?memberToken=...`
- `GET /health`

## Local Development

```sh
npm install
MEMBER_TOKEN_SECRET=dev-secret npm run dev
```

Use this iOS setting for local simulator testing:

```xml
<key>MahjongScoreBaseURL</key>
<string>http://127.0.0.1:8787</string>
```

## Fly.io Deployment

Install and log in:

```sh
brew install flyctl
fly auth login
```

Create the app and volume:

```sh
fly apps create party-games-mahjong-sync --org personal
fly volumes create mahjong_data --region nrt --size 1 --app party-games-mahjong-sync
```

Set the token secret:

```sh
fly secrets set MEMBER_TOKEN_SECRET="$(openssl rand -hex 32)" --app party-games-mahjong-sync
```

Deploy:

```sh
fly deploy --app party-games-mahjong-sync
```

After deploy, verify:

```sh
curl https://party-games-mahjong-sync.fly.dev/health
```

Then update `PartyGamesApp/Info.plist`:

```xml
<key>MahjongScoreBaseURL</key>
<string>https://party-games-mahjong-sync.fly.dev</string>
```

## Notes

- `primary_region = "nrt"` keeps the first deployment in Tokyo, near mainland China among the currently available Fly.io regions.
- `auto_stop_machines = "off"` keeps WebSocket rooms from being interrupted by idle shutdown.
- The SQLite database is stored on the Fly volume mounted at `/data`.
- This is a low-cost validation backend. If the app grows, move persistence to Postgres and use a shared pub/sub layer before scaling to multiple machines.
