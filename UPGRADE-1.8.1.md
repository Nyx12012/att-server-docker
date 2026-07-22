# Upgrading to TavernLauncher v1.8.1

**v1.8.1 is a breaking update: clients on it cannot join servers still running
older patched game folders.** The launcher's join flow now authenticates against
an auth service the *server itself* runs on TCP 1762 (TavernLib v1.3) — old
servers never open 1762, so new clients are rejected. There is no server-side
workaround: **the fix is re-patching your game folder with v1.8.1** and updating
this kit.

## What changed (server-relevant)

- **The server now runs a real auth service on TCP 1762.** Friends' launchers
  connect there before joining: username registration (first join creates an
  account with a per-user token), whitelist/blacklist, join password, optional
  per-IP account limit. Accounts live in `users.json` server-side.
- **`server-config.yaml` is gone** (YamlDotNet removed). Config is now JSON in
  the Wine user's AppData (`…/TheModdingTavern/`):
  - `server_settings.json` — name, `community_listed`, `max_players`,
    `community_listing_token`, `password_hash`, `whitelist_enabled`,
    `enforce_ip_limit`, `public_hostname`
  - `tavern_server.json` — `server_port`
  - `users.json` — friends' registered accounts
  The kit's entrypoint writes the first two from `.env` at every boot and
  preserves the listing token / password hash. All of it sits inside the
  `wineprefix` Docker volume, so it survives restarts — **and wiping that volume
  now wipes your friends' accounts too, not just the world.**
- **Community listing is native and richer.** TavernLib heartbeats the backend
  every ~3 s with live player counts, and the payload now carries a `hostname`
  field — the kit fills it with your IPv4 (`PUBLIC_HOSTNAME`, auto-detected if
  blank), which should end the IPv6-mis-registration problem. Listing on/off is
  the `community_listed` flag now, not the token's presence. Headless servers
  will also appear on the central browser list once that goes live upstream.
- **The separate server description is gone** — the name is all there is.
  `SERVER_DESCRIPTION` in old `.env` files is ignored.

## Upgrade steps

1. **Windows PC:** update TavernLauncher to v1.8.1 (or let it auto-update),
   re-**Patch** your server folder, reinstall your mods, and make a fresh
   `game.zip` (see `MAKE-GAME-ZIP.md`).
2. **Upload it** to the VPS as `~/att-server-docker/game.zip` (or refresh your
   `GAME_URL` copy), and remove/empty the old `./game` folder so the fresh zip
   is what gets extracted:
   ```bash
   cd ~/att-server-docker && docker compose down && rm -rf ./game
   ```
3. **Update the kit and relaunch:**
   ```bash
   git pull && ./install.sh
   ```
   That extracts the new game files, re-opens the firewall (1762 is now a live
   listener and must be reachable — reflected automatically), rebuilds, and
   starts the server.
4. **Provider firewall panels** (DigitalOcean, AWS, Oracle …): if you had to
   open 1757/1761 there, also open **1762/TCP** now.

## Test the listing

```bash
curl "http://themoddingtavern.com:1763/servers/lookup?address=$(curl -4 -s ifconfig.me)"
```

Expect `{"found":true,...}`. If `found:false` after a minute of uptime, enable
the IPv4 heartbeat fallback (`docker compose --profile fallback up -d`) and
check `docker logs att-register`.

## Test a join

The decisive test is a real client on **v1.8.1**: type the VPS IPv4 into the
launcher and Join. The launcher should show it authenticating against your
server (not the old "no official auth service … checking community list"
fallback), then load in. First join registers the player's username with your
server.

## New knobs in `.env`

| Var | Meaning |
|---|---|
| `COMMUNITY_LISTED` | `1` listed / `0` unlisted. Blank = listed if `LISTING_TOKEN` set (old behavior). |
| `PUBLIC_HOSTNAME` | Address the listing advertises. Blank = auto-detect the box's IPv4. |
| `WHITELIST_ENABLED` | `1` = only whitelisted names/IPs may join. |
| `ENFORCE_IP_LIMIT` | `1` = max 4 accounts per source IP. |
| `SERVER_PASSWORD_HASH` | Join-password hash (paste one produced by the launcher's "set password"). |

`SERVER_DESCRIPTION` is retired. `LISTING_TOKEN` still works the same way but
TavernLib now generates one itself if you leave it blank.
