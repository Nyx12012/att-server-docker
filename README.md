# A Township Tale — Dedicated Server (Docker + Wine)

Run a **Modding Tavern** *A Township Tale* server headless on any Linux VPS, in
Docker, under Wine. Friends join by **typing your IP** into the stock
TavernLauncher — no per-friend files to hand out. One command to install; **you
supply your own game files** (this kit ships no game binaries — and since v1.8.1
a clean base install is enough: the container applies the Tavern patch itself on
boot, so kit + game upgrades are just `git pull` and a restart).

> **Never done this before?** Follow **[SETUP-GUIDE.md](SETUP-GUIDE.md)** — a
> step-by-step, zero-experience walkthrough (buy a VPS → run one command → play).
> This README is the technical reference.

> **On TavernLauncher v1.8.1** — a **breaking** update: v1.8.1 clients cannot
> join servers still running older game folders (the server now hosts the auth
> service the launcher requires, on TCP 1762). See
> **[UPGRADE-1.8.1.md](UPGRADE-1.8.1.md)** for what changed and the exact
> command sequence. (`UPGRADE-1.8.0.md` covers the previous hop.)

> **What this is:** deployment tooling only. It contains **no game binaries** — you
> point it at your own copy of the game; the container downloads only Modding
> Tavern's own released patch files. See [NOTICE.md](NOTICE.md).

---

## Quick start (one command)

On a fresh Ubuntu VPS with `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/Nyx12012/att-server-docker/main/install.sh | bash
```

That installs Docker (if missing), clones this repo to `~/att-server-docker`, creates
`.env` with a random per-server listing token, then stops and asks for your game
files. Add them one of two ways:

- **Upload a zip:** put a `game.zip` of your game folder (a clean base install is
  enough — the container patches it at boot) at `~/att-server-docker/game.zip`; **or**
- **Host it yourself:** put a `.zip`/`.tar.gz` of the folder on a private URL **you**
  control (e.g. your own Dropbox direct link) and set `GAME_URL=` in `.env`.

Then set your `SERVER_NAME` in `.env` and run `./install.sh` again. It extracts
the game, opens the firewall, and starts the server, which advertises itself to
the community list natively (the entrypoint writes TavernLib's
`server_settings.json` from your `.env`).

### Or clone-then-run
```bash
git clone https://github.com/Nyx12012/att-server-docker.git
cd att-server-docker
./install.sh /absolute/path/to/patched/game   # optional path arg
```

---

## Getting the game files (you supply these; we ship none)

You need your own copy of the game — `A Township Tale.exe` plus the
`A Township Tale_Data/` folder. A **clean, unpatched backup** of your install is
all it takes: on every start the container checks the folder and applies the
pinned TavernLauncher release itself (MelonLoader, `Plugins/TavernLib.dll`, the
core `Root.Township.dll` patch, and the CircuitsVoiceChat voice mod), exactly
what `TavernLauncher – Server`'s **Patch** + **Mods** buttons do on Windows. It
downloads only Modding Tavern's own released files, skips anything already
current, and never touches your other `Mods/` or `UserData/`.

A folder you already patched with the launcher works too — the patcher just
tops up whatever is missing or outdated (or set `AUTO_PATCH=0` to leave it
entirely alone).

Zip the folder to `game.zip` and upload it to the VPS (or host it privately and
set `GAME_URL`). This is **your** licensed copy — keep it private. Do **not**
redistribute it: ATT being free-to-play does not make its binaries free to
re-host. Each friend who wants to run *their own* server uses their own copy the
same way.

---

## Configuration — `.env`

`.env` (created from `.env.example`) controls everything:

| Var | Meaning |
|---|---|
| `ATT_GAME_DIR` | Path to the game folder. Default `./game`. |
| `GAME_URL` | Optional: URL to a zip/tarball of **your** game folder; auto-downloaded. |
| `AUTO_PATCH` | `1` (default) = bring the game folder to the pinned Tavern release at boot; `0` = boot as-is. |
| `TAVERN_VERSION` | Pinned TavernLauncher release tag (`v1.8.1`); `latest` tracks upstream. Bump deliberately — players must update their launcher in step. |
| `SERVER_NAME` | Name friends see for your server. No quotes; spaces OK. (v1.8.1 dropped the separate description field.) |
| `COMMUNITY_LISTED` | `1` = advertise on the community list, `0` = unlisted. Blank = listed if `LISTING_TOKEN` is set. |
| `PUBLIC_HOSTNAME` | Address the listing advertises (new in v1.8.1). Blank = auto-detect this box's IPv4. |
| `LISTING_TOKEN` | Your private listing key — any long random string, unique to you. Blank = TavernLib generates one on first boot (`install.sh` may also fill it in). |
| `MAX_PLAYERS` | Advertised player cap. |
| `WHITELIST_ENABLED` / `ENFORCE_IP_LIMIT` / `SERVER_PASSWORD_HASH` | v1.8.1 auth-service knobs (see UPGRADE-1.8.1.md). |
| `COMMUNITY_HOST` | Community backend host. Leave as `themoddingtavern.com`. |
| `INSTANCE_ID` / `SERVER_PORT` | Instance id (`-1`) and game port (`1757`) — match the official launcher. |
| `ATT_ACCESS/REFRESH/IDENTITY_TOKEN` | Offline JWTs (leave as-is; they contact no Alta service). |

Manual control instead of the installer:
```bash
cp .env.example .env && nano .env
docker compose up --build -d
docker compose logs -f
docker compose down          # graceful stop
```

---

## How join-by-IP works (no handouts)

Two things together make a friend able to just type your IP and join:

1. **`network_mode: host`** (in `docker-compose.yml`) so the game binds `*:1757`
   dual-stack on the box. Under Docker's default bridge network it binds IPv6-only
   and IPv4 joins silently time out — this is the single most important setting.
2. **The 1762 auth service** (new in v1.8.1). When a friend types your IP, their
   launcher connects to `:1762` on your box, where **your server itself** now runs
   TavernLib's auth service: first join registers their username (an account with
   a per-user token, stored in `users.json` server-side), and whitelist/blacklist/
   password/IP-limit checks happen there. Auth OK → the launcher joins the game on
   1757. This replaces the old dance where 1762 had to sit closed-but-refused and
   the launcher fell back to a community-list lookup.

**The community listing** is now mainly for visibility (the central browser will
show headless servers with live player counts) and as the launcher's lookup
fallback. TavernLib advertises the server itself every ~3 s, and since v1.8.1 the
payload carries the address to advertise — the kit sets it to your IPv4
(`PUBLIC_HOSTNAME`, auto-detected), which fixes the old IPv6 mis-registration. If
the lookup still doesn't show your IPv4, the **`att-register` heartbeat fallback**
re-POSTs it forced over IPv4 — `docker compose --profile fallback up -d`. See
**[UPGRADE-1.8.1.md](UPGRADE-1.8.1.md)**.

Your `LISTING_TOKEN` is a **self-chosen** private string (not issued by anyone); it
just identifies your listing. Each server needs its own; TavernLib auto-generates
one if you leave it blank.

---

## Ports

| Port | Proto | Role | Firewall |
|---|---|---|---|
| 1757 | UDP + TCP | Game traffic (KCP). Players connect here. | **Open** |
| 1761 | TCP | "Forest"/native web server: world & terrain `/cache`. | **Open** (or friends get broken terrain) |
| 1762 | TCP | **TavernLib auth service — LIVE since v1.8.1.** The launcher must reach it to join. | **Open** |
| 1763 | TCP | Community API on `themoddingtavern.com`. | **Outbound only** (don't block egress) |
| 1764 | TCP | Optional admin console (see below). | **Keep closed** (loopback-only) |

**1762 changed meaning in v1.8.1.** It used to be a dead port that merely had to
*refuse* (not drop) the launcher's probe. Now the server binds it and runs the
real auth handshake there — it must be **open and reachable**, including in your
provider's control-panel firewall if it has one. `install.sh` already allows it
in ufw either way.

---

## Upgrading (kit or game)

Everything upgrades from the VPS — the game folder patches itself in place:

```bash
cd ~/att-server-docker
docker compose down && git pull && docker compose build && docker compose up -d
```

When Modding Tavern ships a new TavernLauncher release: wait for this repo to
bump the pinned `TAVERN_VERSION` default (or set it yourself in `.env`), then run
the same three commands. Force a re-patch without waiting for a boot:
`docker compose run --rm att-server update` (server stopped). Remember your
players sit on the same release train — a server version bump usually means they
must update their launcher too.

---

## Testing it works (before giving it to anyone)

1. **Boot and watch logs:**
   ```bash
   docker compose logs -f
   ```
   Healthy signs:
   - `Melon Assembly loaded: 'Plugins/TavernLib.dll'` → MelonLoader injected under Wine.
   - `[entrypoint] wrote server_settings.json (name='…', listed, public_hostname='…')` → native listing configured.
   - `Alta.WebServer.WebServerThread ... Running web server` → web/cache up.
   - Red `webapi.townshiptale.com` errors are **expected** (dead Alta endpoints).

2. **Confirm the listing is live** (from anywhere):
   ```bash
   curl "http://themoddingtavern.com:1763/servers/lookup?address=$(curl -4 -s ifconfig.me)"
   ```
   Expect `{"found":true,"kind":"headless","name":"…","port":1757}`.

3. **Join from a real client** (the decisive test): on a Windows PC, patch the game
   with **TavernLauncher – Client** (v1.8.1+ — the client and server folders must be
   on the same launcher generation), type the VPS **public IP** in the launcher, and
   Join. World loads + you can move around = it works.

4. **Persistence:** build something, `docker compose down`, `up -d`, rejoin — your
   changes persist (world, settings, AND friends' registered accounts all live in
   the `wineprefix` volume — wiping it wipes accounts too).

---

## Optional: admin console

An admin console (run commands like `player list`, spawn items, etc.) can be added
later. It runs on **1764** and must stay **firewalled/loopback-only** — do **not**
`ufw allow 1764`, and never move it onto 1762. It's out of scope for the base
"just host it" flow; see `deploy-console.sh` and the project docs if you want it.

---

## Troubleshooting

- **Players can't connect:** confirm host networking is active
  (`docker exec att-server ss -lun | grep 1757` shows `*:1757`), and that 1757
  UDP **and** TCP are open in both ufw **and** your provider's firewall panel.
- **Broken/no terrain but buildings load:** 1761/tcp isn't open — friends can't pull
  the world cache. `ufw allow 1761/tcp && ufw reload`.
- **Join fails / launcher "hangs" or errors on authenticating:** the launcher can't
  reach your server's 1762 auth service. Check it's listening
  (`docker exec att-server ss -ltn | grep 1762`), that ufw allows 1762/tcp, AND your
  provider's panel firewall does too. A v1.8.1 client against an old (pre-1.8.1)
  game folder also fails exactly here — with `AUTO_PATCH=1` that shouldn't happen;
  check the boot log's `[patcher]` lines and `./game/.tavern-patch-version`.
- **A friend gets "Name taken … or you lost the token to your account":** someone
  already registered that username on your server (accounts live in `users.json`),
  or they reinstalled and lost their local token. Pick another name, or clear their
  entry server-side.
- **Not listed:** confirm the listing points at
  your IPv4 — `curl "http://themoddingtavern.com:1763/servers/lookup?address=$(curl -4 -s ifconfig.me)"`.
  If `found:false`, check `PUBLIC_HOSTNAME` resolved in the entrypoint log line; if
  it still won't stick, enable the IPv4 heartbeat fallback:
  `docker compose --profile fallback up -d` (then `docker logs att-register`).
  Ensure outbound access to `themoddingtavern.com:1763`.
- **No `TavernLib` line / mods don't load:** the game folder is missing `version.dll`
  (MelonLoader), or `WINEDLLOVERRIDES="version=n,b"` isn't set (it is, in the Dockerfile).
- **Crash during Unity init:** uncomment `RUN winetricks -q vcrun2019` in the
  Dockerfile and `docker compose build --no-cache`.
- **Wine faults early (ptrace/seccomp):** uncomment `cap_add: [SYS_PTRACE]` and
  `security_opt: [seccomp:unconfined]` in `docker-compose.yml`.
- **Voice chat:** v1.8.x uses CircuitLord's **official** voice (CircuitsVoiceChat) —
  it rides the game's own channel (port 1757), so there's nothing to run or open
  server-side, and the auto-patcher installs it in the server folder for you. If
  someone can't be heard, make sure *they* installed the voice mod when patching
  their client (it's the first *optional* mod in the launcher). The old
  self-hosted `att-voice` relay is gone.

---

## Files

| File | Role |
|---|---|
| `SETUP-GUIDE.md` | **Start here if you're new** — zero-experience step-by-step. |
| `UPGRADE-1.8.1.md` | **v1.8.1 specifics: the 1762 auth service, JSON config, `public_hostname`, commands.** |
| `UPGRADE-1.8.0.md` | The previous hop (native listing, voice, `users.json`). |
| `install.sh` | One-command installer (Docker + repo + .env + token + game files + firewall + up). |
| `patcher.sh` | Brings the game folder to the pinned TavernLauncher release at boot (core patch, TavernLib, MelonLoader, voice). |
| `register.sh` | The IPv4 listing heartbeat — **fallback** only, run via `--profile fallback`. |
| `Dockerfile` | Ubuntu 22.04 + winehq-stable + Xvfb; seeds the Wine prefix. |
| `entrypoint.sh` | Runs the patcher, writes `server_settings.json`/`tavern_server.json` from `.env`, starts Xvfb, launches the server, streams logs, handles SIGTERM. |
| `docker-compose.yml` | Server + opt-in register fallback, host networking, volumes, env. |
| `.env.example` | Config template (tokens, game path, server name, listing token). |
| `.gitignore` | Blocks `.env`, `game/`, and archives from commits. |
| `NOTICE.md` | Why no game files are included. |
