# Upgrading to TavernLauncher v1.8.1

**v1.8.1 is a breaking update: clients on it cannot join servers still running
older patched game folders.** The launcher's join flow now authenticates against
an auth service the *server itself* runs on TCP 1762 (TavernLib v1.3) — old
servers never open 1762, so new clients are rejected. The fix is getting your
game folder onto the v1.8.1 patch and updating this kit — **and the kit now does
the patching itself**: on boot the container brings the mounted game folder to
the pinned TavernLauncher release (MelonLoader, TavernLib, the core
`Root.Township.dll` patch, the voice mod), downloading only Modding Tavern's own
released files. No Windows re-patch, no new `game.zip`.

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

On the VPS — your existing game folder upgrades in place:

```bash
cd ~/att-server-docker
docker compose down
git pull
docker compose build
docker compose up -d
docker compose logs -f     # watch for "[patcher] done" then the normal boot
```

The first boot downloads the v1.8.1 server package from Modding Tavern's GitHub
(~a minute), applies it to `./game`, writes the new JSON config from your `.env`,
and starts. Your world, your own mods in `Mods/`, and `UserData/` are untouched.

Two things to check once:

1. **Provider firewall panels** (DigitalOcean, AWS, Oracle …): if you had to
   open 1757/1761 there, also open **1762/TCP** now — the auth service is a live
   listener the launcher must reach. (ufw is handled if you ran `./install.sh`;
   `sudo ufw allow 1762/tcp` covers a hand-rolled firewall.)
2. **Your `.env` still has old knobs?** `SERVER_DESCRIPTION` is dead (ignored);
   see "New knobs" below for what replaced what. `git pull` never touches your
   `.env`.

To re-patch on demand later (e.g. after bumping `TAVERN_VERSION`):

```bash
docker compose down
docker compose run --rm att-server update
docker compose up -d
```

Prefer patching on Windows yourself? Set `AUTO_PATCH=0` in `.env` and the
container boots whatever you put in the folder, exactly like the old kit.

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
| `AUTO_PATCH` | `1` (default) = keep the game folder on the pinned Tavern release at boot. `0` = boot as-is. |
| `TAVERN_VERSION` | The pinned TavernLauncher release tag (`v1.8.1`). `latest` tracks upstream — bump deliberately; a new release usually means players must update their launcher too. |
| `COMMUNITY_LISTED` | `1` listed / `0` unlisted. Blank = listed if `LISTING_TOKEN` set (old behavior). |
| `PUBLIC_HOSTNAME` | Address the listing advertises. Blank = auto-detect the box's IPv4. |
| `WHITELIST_ENABLED` | Informational flag in TavernLib v1.3 — what actually gates joins is the whitelist name/IP lists inside `users.json` (empty lists = no gate). |
| `ENFORCE_IP_LIMIT` | **Leave `0`.** TavernLib v1.3 has a counting bug: with this on, every join is rejected once 5+ users are registered. |
| `SERVER_PASSWORD_HASH` | Join-password hash (paste one produced by the launcher's "set password"). |

`SERVER_DESCRIPTION` is retired. `LISTING_TOKEN` still works the same way but
TavernLib now generates one itself if you leave it blank.
