# A Township Tale — Dedicated Server (Docker + Wine)

Run a **Modding Tavern** *A Township Tale* server headless on any Linux VPS, in
Docker, under Wine. Friends join by **typing your IP** into the stock
TavernLauncher — no per-friend files to hand out. One command to install; **you
supply your own patched game files** (this kit ships no game binaries).

> **Never done this before?** Follow **[SETUP-GUIDE.md](SETUP-GUIDE.md)** — a
> step-by-step, zero-experience walkthrough (buy a VPS → run one command → play).
> This README is the technical reference.

> **On TavernLauncher v1.8.0** (native community listing + description, official
> voice, unified `users.json`). See **[UPGRADE-1.8.0.md](UPGRADE-1.8.0.md)** for
> the v1.8.0 specifics and the exact command sequence.

> **What this is:** deployment tooling only. It contains **no game binaries** — you
> point it at your own patched game folder. See [NOTICE.md](NOTICE.md).

---

## Quick start (one command)

On a fresh Ubuntu VPS with `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/Nyx12012/att-server-docker/main/install.sh | bash
```

That installs Docker (if missing), clones this repo to `~/att-server-docker`, creates
`.env` with a random per-server listing token, then stops and asks for your game
files. Add them one of two ways:

- **Upload a zip:** put a `game.zip` of your patched folder at `~/att-server-docker/game.zip`; **or**
- **Host it yourself:** put a `.zip`/`.tar.gz` of the folder on a private URL **you**
  control (e.g. your own Dropbox direct link) and set `GAME_URL=` in `.env`.

Then set your `SERVER_NAME` (and `SERVER_DESCRIPTION`) in `.env` and run
`./install.sh` again. It extracts the game, opens the firewall, and starts the
server, which advertises itself to the community list via `server-config.yaml`.

### Or clone-then-run
```bash
git clone https://github.com/Nyx12012/att-server-docker.git
cd att-server-docker
./install.sh /absolute/path/to/patched/game   # optional path arg
```

---

## Getting the patched game files (you make these; we ship none)

The game is Windows software patched by the Modding Tavern **TavernLauncher**. To
produce the folder this server needs, on **your own Windows PC**:

1. Install *A Township Tale* (free on Steam), run **TavernLauncher – Server**, hit
   **Patch** (then **Mods** if you use any). That yields a folder with
   `A Township Tale.exe`, `version.dll` (MelonLoader), `A Township Tale_Data/`,
   `MelonLoader/`, `Plugins/TavernLib.dll`, `UserLibs/`, `Mods/`, `UserData/`.
2. Zip that folder to `game.zip` and upload it to the VPS (or host it and set `GAME_URL`).

This is **your** licensed copy — keep it private. Do **not** redistribute it: ATT
being free-to-play does not make its binaries free to re-host. Each friend who wants
to run *their own* server makes their own patched folder the same way.

---

## Configuration — `.env`

`.env` (created from `.env.example`) controls everything:

| Var | Meaning |
|---|---|
| `ATT_GAME_DIR` | Path to the patched game folder. Default `./game`. |
| `GAME_URL` | Optional: URL to a zip/tarball of **your** game folder; auto-downloaded. |
| `SERVER_NAME` | Name friends see for your server. No quotes; spaces OK. |
| `SERVER_DESCRIPTION` | Short blurb shown next to your server in the community list (new in v1.8.0). |
| `LISTING_TOKEN` | Your private listing key — any long random string, unique to you. `install.sh` fills this in automatically if blank. Its presence turns community advertising on; blank = unlisted. |
| `MAX_PLAYERS` | Advertised player cap (cosmetic for the listing). |
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
2. **A community listing** so the launcher can find your box. When a friend types
   your IP, their launcher first probes `:1762` for an auth service; a headless
   server never answers there, so the launcher asks the backend "is this IP a known
   headless server?" — a live listing is what makes that answer **yes**, and the
   launcher then joins directly with no auth handshake. On v1.8.0 the server
   advertises itself (native listing, from `server-config.yaml`). If that registers
   over IPv6 (common on VPSes), the **`att-register` heartbeat fallback** re-POSTs it
   forced over IPv4 — enable it with `docker compose --profile fallback up -d`.
   See **[UPGRADE-1.8.0.md](UPGRADE-1.8.0.md)**.

Your `LISTING_TOKEN` is a **self-chosen** private string (not issued by anyone); it
just identifies your listing. Each server needs its own.

---

## Ports

| Port | Proto | Role | Firewall |
|---|---|---|---|
| 1757 | UDP + TCP | Game traffic (KCP). Players connect here. | **Open** |
| 1761 | TCP | "Forest"/native web server: world & terrain `/cache`. | **Open** (or friends get broken terrain) |
| 1762 | TCP | Auth probe. Nothing listens (server is offline-mode). | **Allow, don't drop** — see below |
| 1763 | TCP | Community API on `themoddingtavern.com`. | **Outbound only** (don't block egress) |
| 1764 | TCP | Optional admin console (see below). | **Keep closed** (loopback-only) |

**The 1762 gotcha (`install.sh` handles this for you):** nothing runs on 1762, but
you must **allow** it in the firewall, not drop it. The launcher's probe needs an
instant *connection refused* (the kernel's RST from a closed port). If the firewall
silently **drops** 1762 instead, the probe hangs and the join-by-IP fallback can
fail. So: allowed + nothing listening = refused = correct.

---

## Testing it works (before giving it to anyone)

1. **Boot and watch logs:**
   ```bash
   docker compose logs -f
   ```
   Healthy signs:
   - `Melon Assembly loaded: 'Plugins/TavernLib.dll'` → MelonLoader injected under Wine.
   - `[entrypoint] wrote server-config.yaml (name='…', listed)` → native listing configured.
   - `Alta.WebServer.WebServerThread ... Running web server` → web/cache up.
   - Red `webapi.townshiptale.com` errors are **expected** (dead Alta endpoints).

2. **Confirm the listing is live** (from anywhere):
   ```bash
   curl "http://themoddingtavern.com:1763/servers/lookup?address=$(curl -4 -s ifconfig.me)"
   ```
   Expect `{"found":true,"kind":"headless","name":"…","port":1757}`.

3. **Join from a real client** (the decisive test): on a Windows PC, patch the game
   with **TavernLauncher – Client**, type the VPS **public IP** in the launcher, and
   Join. World loads + you can move around = it works.

4. **Persistence:** build something, `docker compose down`, `up -d`, rejoin — your
   changes persist (world lives in the `wineprefix` volume).

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
- **Join fails, launcher "hangs" authenticating:** your firewall is dropping 1762
  instead of refusing it. `ufw allow 1762/tcp` (see the 1762 gotcha above).
- **Not listed / friends' IP-join fails immediately:** confirm the listing points at
  your IPv4 — `curl "http://themoddingtavern.com:1763/servers/lookup?address=$(curl -4 -s ifconfig.me)"`.
  If `found:false`, the native listing likely went out over IPv6; enable the IPv4
  heartbeat fallback: `docker compose --profile fallback up -d` (then `docker logs
  att-register`). Ensure outbound access to `themoddingtavern.com:1763`.
- **No `TavernLib` line / mods don't load:** the game folder is missing `version.dll`
  (MelonLoader), or `WINEDLLOVERRIDES="version=n,b"` isn't set (it is, in the Dockerfile).
- **Crash during Unity init:** uncomment `RUN winetricks -q vcrun2019` in the
  Dockerfile and `docker compose build --no-cache`.
- **Wine faults early (ptrace/seccomp):** uncomment `cap_add: [SYS_PTRACE]` and
  `security_opt: [seccomp:unconfined]` in `docker-compose.yml`.
- **Voice chat:** v1.8.0 uses CircuitLord's **official** voice (CircuitsVoiceChat),
  installed as a mod in your patched game folder — it rides the game's own channel
  (port 1757), so there's nothing to run or open server-side. If someone can't be
  heard, make sure they installed the voice mod when patching (it's the first
  *optional* mod in the launcher). The old self-hosted `att-voice` relay is gone.

---

## Files

| File | Role |
|---|---|
| `SETUP-GUIDE.md` | **Start here if you're new** — zero-experience step-by-step. |
| `UPGRADE-1.8.0.md` | v1.8.0 specifics: native listing, description, voice, `users.json`, commands. |
| `install.sh` | One-command installer (Docker + repo + .env + token + game files + firewall + up). |
| `register.sh` | The IPv4 join-by-IP heartbeat — **fallback** only, run via `--profile fallback`. |
| `Dockerfile` | Ubuntu 22.04 + winehq-stable + Xvfb; seeds the Wine prefix. |
| `entrypoint.sh` | Writes `server-config.yaml` from `.env`, starts Xvfb, launches the server, streams logs, handles SIGTERM. |
| `docker-compose.yml` | Server + opt-in register fallback, host networking, volumes, env. |
| `.env.example` | Config template (tokens, game path, server name, listing token). |
| `.gitignore` | Blocks `.env`, `game/`, and archives from commits. |
| `NOTICE.md` | Why no game files are included. |
