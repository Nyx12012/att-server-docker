# A Township Tale — Dedicated Server (Docker + Wine)

Run a **default Modding Tavern v1.6.2** *A Township Tale* server headless on any
Linux box, in Docker, under Wine. One command to install; you supply your own
patched game files.

> **What this is:** deployment tooling only. It contains **no game binaries** — you
> point it at your own patched game folder (or a URL you host). See [NOTICE.md](NOTICE.md).
>
> **Status:** the server boot path matches the official `startServer.bat` and proven
> prior art, but the Linux/Wine build has not been CI-tested — your first run is the
> real test. Community listing + server name are **not wired up yet** (see below).

---

## Quick start (one command)

On a fresh Linux VPS with `curl` + `git`:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/att-server-docker/main/install.sh | bash
```

That installs Docker (if missing), clones this repo to `~/att-server-docker`, creates
`.env`, then stops and tells you to add your game files. Add them one of two ways:

- **You have the patched folder already:** copy it to `~/att-server-docker/game/`
  (so `game/A Township Tale.exe` exists), then run `./install.sh` again; **or**
- **Host it yourself:** put a `.zip`/`.tar.gz` of the folder on a URL you control,
  set `GAME_URL=` in `.env`, then run `./install.sh` again — it downloads + extracts.

That's it — it builds and starts the server. To hand this to a friend, they run the
exact same one-liner (with your repo URL) and supply their own game files.

### Or clone-then-run
```bash
git clone https://github.com/YOUR_GITHUB_USER/att-server-docker.git
cd att-server-docker
./install.sh /absolute/path/to/patched/game   # optional path arg
```

---

## Getting the patched game files

The game itself is Windows software patched by the Modding Tavern **TavernLauncher**.
To produce the folder this server needs:

1. On Windows, install *A Township Tale*, run **TavernLauncher – Client/Server**, hit
   **Patch** then **Mods**. That yields a folder with `A Township Tale.exe`,
   `version.dll` (MelonLoader), `A Township Tale_Data/`, `MelonLoader/`,
   `Plugins/TavernLib.dll`, `UserLibs/`, an (empty) `Mods/`, `UserData/`.
2. Zip that folder and either copy it to the server's `game/` dir or host it and set
   `GAME_URL`. This is your licensed copy — keep it private.

---

## Setup details

`.env` (created from `.env.example`) controls everything:

| Var | Meaning |
|---|---|
| `ATT_GAME_DIR` | Path to the patched game folder. Default `./game`. |
| `GAME_URL` | Optional: URL to a zip/tarball of the game folder; auto-downloaded. |
| `INSTANCE_ID` | Server instance id (default `-1`, matches the official launcher). |
| `SERVER_PORT` | Game port (default `1757`). |
| `ATT_ACCESS/REFRESH/IDENTITY_TOKEN` | Offline JWTs (leave as-is; they hit no Alta service). |
| `SERVER_NAME`, `COMMUNITY_*` | Placeholders for listing — **not active yet** (see below). |

Manual control instead of the installer:
```bash
cp .env.example .env && nano .env
docker compose up --build -d
docker compose logs -f
docker compose down          # graceful stop
```

---

## Testing it works (do this before giving it to anyone)

1. **Boot the container** and watch logs:
   ```bash
   docker compose logs -f
   ```
   Healthy signs:
   - `Melon Assembly loaded: 'Plugins/TavernLib.dll'` → MelonLoader injected under
     Wine (the #1 risk; if missing, it's the `WINEDLLOVERRIDES` — already set).
   - `Alta.WebServer.WebServerThread ... Running web server` → console/web up.
   - Red `webapi.townshiptale.com` errors are **expected** (dead Alta endpoints).

2. **Check the game port is listening** inside the box:
   ```bash
   docker exec att-server bash -c "ss -lun | grep 1757 || true"
   ```

3. **Join from a real client** (the decisive test): on your Windows PC, use the
   patched **Client** launcher, add a server by the VPS **public IP**, port **1757**,
   and connect. If the world loads and you can move around, the server works.

4. **Persistence check:** build something, `docker compose down`, `up -d`, rejoin —
   your changes should still be there (world lives in the `wineprefix` volume).

If 1–3 pass, ship it to your friend. If step 1 shows a Wine/Unity crash, see
Troubleshooting.

---

## Ports (per the devs)

| Port | Proto | Role | Expose to internet? |
|---|---|---|---|
| 1757 | UDP (+TCP) | Game traffic (KCP). Players connect here. | **Yes** |
| 1761 | TCP | "Forest" / native web server: `/cache` + Alta console REST. | Only if needed |
| 1762 | TCP | Auth. | Keep private |
| 1763 | TCP | Community API → **themoddingtavern.com** backend. | See below |

Open **1757** (UDP+TCP) to the world. Keep 1761/1762 private unless you need remote
console. For community listing you'll also need **outbound** internet to
`themoddingtavern.com` (don't firewall egress if you want to be listed).

---

## Server name & community listing — honest status

**Not working yet in this headless build, and here's why:** the display **name**,
`community_listed`, and `public_hostname` are settings the **Windows launcher** reads
from its `server_settings.json`. The game's own config files
(`ServerConfiguration.json`, `GameConfiguration.json`) have **no name field**, and the
launcher-generated `startServer.bat` passes **no** name/listing flags to the game. So:

- On a **direct-IP** server (what this repo gives you today), there is no display name —
  players join by IP. That works now.
- **Community listing + a shown name** are done by the launcher process talking to the
  community backend (the devs say port **1763 / themoddingtavern.com**). We have **not**
  reverse-engineered that registration call yet, so this repo does not perform it. The
  `SERVER_NAME`/`COMMUNITY_*` vars in `.env` are placeholders for when we do.

**To finish this feature**, the next step is to extract the launcher's Python
(it's PyInstaller) and read exactly how it registers a server with
`themoddingtavern.com:1763` — then we replicate that call (a small sidecar or an
entrypoint step) so the container self-lists with your chosen name. Ask and that
becomes the next task.

---

## Troubleshooting

- **No `TavernLib` line / mods don't load:** confirm the game folder has `version.dll`
  (MelonLoader) and that `WINEDLLOVERRIDES="version=n,b"` is in the Dockerfile (it is).
- **Crash during Unity init:** uncomment `RUN winetricks -q vcrun2019` in the Dockerfile
  and rebuild (`docker compose build --no-cache`).
- **Wine faults early (ptrace/seccomp):** uncomment `cap_add: [SYS_PTRACE]` and
  `security_opt: [seccomp:unconfined]` in `docker-compose.yml`.
- **Players can't connect:** open 1757 UDP **and** TCP in the VPS firewall/security
  group; verify with `docker exec att-server ss -lun | grep 1757`.
- **Voice chat missing:** expected — Vivox voice depended on Alta's cloud.

---

## Files

| File | Role |
|---|---|
| `install.sh` | One-command installer (Docker + repo + .env + game files + up). |
| `Dockerfile` | Ubuntu 22.04 + winehq-stable + Xvfb; seeds the Wine prefix. |
| `entrypoint.sh` | Starts Xvfb, launches the server, streams logs, handles SIGTERM. |
| `docker-compose.yml` | Service, volumes, ports, env. |
| `.env.example` | Config template (tokens, game path, ports, listing placeholders). |
| `.gitignore` | Blocks `.env` and `game/` from commits. |
| `NOTICE.md` | Why no game files are included. |
