# Upgrading to TavernLauncher v1.8.2

Smaller than the 1.8.1 jump — the auth service, the JSON config and the native
listing all work the way they did. The headline for a server operator is a **new
WebSocket console on TCP 1760**, and two new credential files to keep private.

**Update your players' launchers too.** The launcher release pins both the client
and server patches, and the 1.8.0 → 1.8.1 step already proved a mismatch can
refuse joins outright. Bump together.

## Upgrade steps

Your existing game folder upgrades in place — the container re-patches it on
boot, so there is no Windows re-patch and no new `game.zip`:

```bash
cd ~/att-server-docker && docker compose down && git pull && docker compose up -d --build
```

Watch it land:

```bash
docker compose logs -f
```

Look for `[patcher] downloading TavernLauncher v1.8.2 server package…` on the
first boot after the bump, then `Melon Assembly loaded: 'Plugins/TavernLib.dll'`.
On later boots the patcher prints `already patched for TavernLauncher v1.8.2` and
does nothing — it is a no-op once current, which is why it is safe on every boot.

To force a re-patch without changing the pin (repairs a half-patched folder):

```bash
docker compose run --rm att-server update
```

## What changed (server-relevant)

- **A WebSocket console on TCP 1760.** TavernLib now serves a remote console
  there. **This kit does not open 1760, on purpose** — see Firewall below.
- **Two new credential files**, created by TavernLib on first boot, alongside
  `server_settings.json` in the wineprefix volume:

  | File | What it is |
  |---|---|
  | `…/TheModdingTavern/server_secret.key` | HMAC key that signs the console token |
  | `…/TheModdingTavern/console_token.txt` | a console login that **never expires** |

  Anyone holding either owns the server. The volume already stored your friends'
  accounts (`users.json`); now it stores console credentials too. **Treat it as a
  credential store: never share it, never commit it, never bake it into an
  image.** The kit's `.gitignore` covers stray copies.
- **Community listing calls now honour a Windows system proxy.** Irrelevant under
  Wine in this container — it reads `ProxyEnable` from the registry, finds it 0,
  and behaves exactly as before.

## The TavernLib version is confusing — read this before you pin

`TAVERN_VERSION` pins the **launcher** release, and the launcher decides which
TavernLib you get. Those two version lines move independently, and TavernLib's
own self-reported version has lagged its tag more than once — **the TavernLib
bundled in v1.8.2 reports `v1.4.0`.** A newer TavernLib may exist upstream
without a launcher release carrying it yet.

Practically: pin `TAVERN_VERSION` to a launcher tag you have actually booted, and
treat `latest` as a thing you opt into deliberately, not a default. Do not try to
match a TavernLib version number — you cannot select one from here, and the
version string is not a reliable identifier anyway.

## Firewall

Unchanged from 1.8.1, with one addition: **leave 1760 closed.**

| Port | State | Why |
|---|---|---|
| 1757 TCP+UDP | open | the game itself (voice rides this channel) |
| 1761 TCP | open | world/terrain cache download |
| 1762 TCP | **open** | the auth service — this is the join path, it cannot be closed |
| 1760 TCP | **closed** | the new console. Reach it over an SSH tunnel instead |
| 1763 | outbound only | community API |

`install.sh` configures exactly this. `docker-compose.yml` uses
`network_mode: host`, so there is no Docker NAT chain quietly bypassing `ufw` —
the rules you set are the rules that apply. Verify with `sudo ufw status verbose`.

If your provider has its own firewall panel (DigitalOcean, AWS, Oracle …), it
needs the same set — and it should **not** list 1760.

## Shutdown

`docker-compose.yml` now sets `stop_grace_period: 120s`. Docker's default is 10
seconds and then SIGKILL, which is not enough for a Unity world to flush a save,
and TavernLib makes shutdown slower still: it asks the community backend to
de-list the server and cancels the first quit request while that is in flight.

A SIGKILL part-way through a save is how worlds get corrupted, so give it room.
**Time your first `docker compose down`** — if it consistently runs to the full
grace period rather than exiting on its own, raise it further and say so in an
issue upstream.

## Join password

The stored `password_hash` is a **double SHA-256**: the launcher hashes the
password client-side and the server hashes that hex string again. The easy path
is the launcher's "set password" button — copy the `password_hash` it writes into
`SERVER_PASSWORD_HASH`. By hand:

```bash
printf %s "$(printf %s 'yourpassword' | sha256sum | cut -d' ' -f1)" | sha256sum | cut -d' ' -f1
```

Two traps:

- **Blank in `.env` does not remove a password.** The entrypoint falls back to the
  hash already in `server_settings.json`. To actually remove one, clear it in
  both places.
- It is unsalted, and the value that crosses 1762 is directly replayable. It is a
  squatter gate, not a secret — do not reuse a password that matters.

## Two settings that still do not behave the way they read

Both verified against the shipped TavernLib, both unchanged in 1.8.2:

- **`ENFORCE_IP_LIMIT` — leave it 0.** The check counts wrong: it projects every
  registered user to a true/false and then counts the whole list. Once more than
  four accounts exist *in total*, it rejects **every** join, not just repeat
  accounts from one address.
- **`WHITELIST_ENABLED` does nothing.** It is written to `server_settings.json`
  and never read back. What actually gates joins is the whitelist inside
  `users.json`: if `whitelist.usernames` or `whitelist.ips` is non-empty, only
  those may join — whatever this flag says. Those usernames are matched
  **case-sensitively**, so `Nyx` will not admit someone joining as `nyx`.
