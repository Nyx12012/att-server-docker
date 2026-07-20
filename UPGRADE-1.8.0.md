# Upgrading to TavernLauncher v1.8.0

This kit now targets the Modding Tavern **TavernLauncher v1.8.0** release. Here's
what changed, the exact commands to run, and how to set a description + get on the
community server list.

---

## What changed in this kit

| Area | Before | Now (v1.8.0) |
|---|---|---|
| **Voice** | Our self-hosted `att-voice` relay + `TavernVoice.dll` client mod | **Removed.** v1.8.0 ships CircuitLord's official voice (CircuitsVoiceChat) inside your patched game folder. It rides the game's own network channel (port 1757) — no relay, no extra port. |
| **Community listing** | `att-register` heartbeat POSTing every 30s (required) | **Native listing by default.** The entrypoint writes `server-config.yaml` from your `.env`, so TavernLib advertises the server itself. The heartbeat is still here as a one-command **fallback**. |
| **Description** | Not supported (listing showed name only) | **Supported** — set `SERVER_DESCRIPTION` in `.env`. |
| **Whitelist / bans** | separate `Whitelist.json` / `Blacklist.json` | v1.8.0 unified these into a single **`users.json`** (see below). |
| **Launcher files** | scattered | The Windows launcher now keeps its files under `%appdata%\TheModdingTavern\`. Only matters when you make the game folder on Windows; the headless server is unaffected. |
| **Image tag** | `att-server:1.6.2` | `att-server:1.8.0` |

> **Heads-up (honest expectation):** v1.8.0 updated the *launcher*, not `TavernLib`
> — the shipped `TavernLib.dll` is byte-identical to the previous one, which is why
> the changelog marks live playercounts / tavernToken / roles as *"Pending TavernLib
> update."* So the **native listing uses the same code that historically registered
> over IPv6** on our VPS. It's worth testing (below); if it lists the wrong address,
> flip on the IPv4 heartbeat fallback and you're exactly where the old kit was.

---

## 1. Re-patch your game folder with v1.8.0 (on Windows)

The server runs *your* patched game folder — the v1.8.0 mods live there, not in this
image. So make a fresh one:

1. Open **TavernLauncher – Server** (v1.8.0) → point it at your `A Township Tale.exe`.
2. **Patch**, then **Mods** → install all the **required** mods top to bottom.
   (CircuitLord's voice is the first **optional** mod — install it if you want voice.)
3. Confirm the folder has `A Township Tale.exe`, `version.dll`, `Plugins\TavernLib.dll`.
4. Zip it to `game.zip` (see [MAKE-GAME-ZIP.md](MAKE-GAME-ZIP.md)). Keep it private.

Then upload it to the server the same way as before (`scp` or a private `GAME_URL`).

---

## 2. The commands to stand it up

On a fresh Ubuntu 22.04 VPS (full first-timer walkthrough is in
[SETUP-GUIDE.md](SETUP-GUIDE.md)):

```bash
# 1. Bootstrap (installs Docker, clones the repo, makes .env, then stops for game files)
curl -fsSL https://raw.githubusercontent.com/Nyx12012/att-server-docker/main/install.sh | bash

# 2. Upload your patched game.zip (run this in a SECOND window, from your PC)
scp "C:\path\to\game.zip" root@YOUR.VPS.IP:~/att-server-docker/game.zip

# 3. Set the name + description friends will see
cd ~/att-server-docker
sed -i 's/^SERVER_NAME=.*/SERVER_NAME=Velaris Township/'                 .env
sed -i 's/^SERVER_DESCRIPTION=.*/SERVER_DESCRIPTION=Cozy modded co-op/'  .env

# 4. Build + launch (opens the firewall, starts the server, writes server-config.yaml)
./install.sh

# 5. Watch it boot
docker compose logs -f      # Ctrl+C stops watching, not the server

# 6. Confirm your listing points at THIS box's IPv4 (see "Test the listing" below)
curl "http://themoddingtavern.com:1763/servers/lookup?address=$(curl -4 -s ifconfig.me)"
```

That's the whole loop. `docker compose down` / `up -d` stop and start it later.

---

## Setting the name and description

Both live in `.env` and flow into `server-config.yaml` on every boot:

```bash
sed -i 's/^SERVER_NAME=.*/SERVER_NAME=Your Server Name/'          .env
sed -i 's/^SERVER_DESCRIPTION=.*/SERVER_DESCRIPTION=Your blurb/'   .env
docker compose up -d        # re-reads .env and rewrites server-config.yaml
```

Spaces are fine; no quotes needed. (Prefer an editor? `nano .env`, edit the two
lines, Ctrl+O / Enter / Ctrl+X, then `docker compose up -d`.)

---

## Getting on the community server list

**How it works now:** with a `LISTING_TOKEN` set (install.sh generates one for you),
the entrypoint writes it into `server-config.yaml`, and TavernLib advertises your
server to `themoddingtavern.com` — name, description, and player cap included. To run
**unlisted** (direct-IP only), blank out `LISTING_TOKEN` in `.env` and restart.

### Test the listing

After the server has been up ~1 minute:

```bash
curl "http://themoddingtavern.com:1763/servers/lookup?address=$(curl -4 -s ifconfig.me)"
```

- **`{"found":true,...}`** with your name → 🎉 native listing works. Done.
- **`{"found":false}`** (or it lists an IPv6 address) → your box advertised over IPv6,
  which friends typing your IPv4 won't match. Turn on the IPv4 heartbeat fallback:

  ```bash
  docker compose --profile fallback up -d      # starts att-register alongside the server
  ```

  Re-run the lookup after ~30s; it should now be `found:true`. To stop the fallback:
  `docker compose --profile fallback down` (or just `docker compose down`).

Direct-IP joining (a friend typing your IP) also depends on the lookup returning
`found:true`, so use the same test to know friends can get in.

---

## Whitelist / bans (`users.json`)

v1.8.0 merged `Whitelist.json` + `Blacklist.json` into one **`users.json`** in your
game folder (under `UserData\`). Easiest way to manage it is the **TavernLauncher –
Server** GUI's user menu on Windows before you zip, or the in-game/console admin
tools. Edit it on the VPS only if you know the format; a malformed `users.json` can
stop logins. It is **not** managed by this kit's `.env`.

---

## Pushing this update to GitHub

These changes are staged in your local clone. Review and push to the existing repo:

```bash
cd ~/att-server-docker     # or wherever your clone is
git status                 # see what changed (voice files removed, configs updated, this doc added)
git add -A
git commit -m "Update kit for TavernLauncher v1.8.0: native listing + description, official voice, drop att-voice"
git push
```

Nothing here is committed or pushed for you — that's yours to review and run.
