# Upgrading to TavernLauncher v1.8.3

Two things make this hop different from 1.8.2:

1. **It is a hard compatibility break.** TavernLib widened the per-message type
   field on the KCP game channel (5 → 8 bits, making room for its own new
   messages like role sync). A 1.8.2 client and a 1.8.3 server no longer parse
   each other's traffic — joins don't degrade, they fail. **Everyone updates
   together, same day.**
2. **The launcher-bundled TavernLib is broken, and the kit now works around
   that class of problem permanently.** v1.8.3 ships the TavernLib v1.5.0
   build, whose join validation rejects **brand-new joiners** (first-time
   accounts hit "Data mismatch or account not found"). The fix, v1.5.1, was
   released hours later — but only as a **release asset**; its git tag points
   at the same commit as v1.5.0. The kit therefore installs a pinned TavernLib
   release asset *over* the bundled DLL, sha256-verified
   (`TAVERNLIB_VERSION` / `TAVERNLIB_SHA256` in `.env`, default `v1.5.1`).

## Upgrade steps

Same as always — the container re-patches the mounted game folder on boot:

```bash
cd ~/att-server-docker && docker compose down && git pull && docker compose up -d --build
```

Watch it land:

```bash
docker compose logs -f
```

First boot after the bump prints `[patcher] downloading TavernLauncher v1.8.3
server package…` then `[patcher] overlaying TavernLib v1.5.1 release asset…`.
Later boots print `already patched for TavernLauncher v1.8.3+tavernlib-v1.5.1`
— note the stamp format now records both pins. Force a re-patch without
changing pins (repairs a half-patched folder):

```bash
docker compose run --rm att-server update
```

**Tell your players before you flip.** Their launcher must be on 1.8.3 or they
cannot join at all — this is not the usual "usually update together", it is a
protocol change.

## What changed (server-relevant)

- **Roles.** Accounts in `users.json` can now carry roles (`owner`,
  `moderator`, `fly`, or your own). Upstream uses them for the re-introduced
  **fly mode** launch option (players with `fly`/`moderator`/`owner` may use
  it) and for moderator-visible server settings. Assign roles from
  TavernKeeper's players menu — which talks to the 1760 console, so from this
  kit you reach it over the usual SSH tunnel; 1760 stays closed.
- **Whitelist applications.** The auth pong now advertises
  `whitelist_enabled`, and launchers offer joiners an "apply for whitelist"
  flow. Applications land in `whitelist_requests.json` next to `users.json` in
  the wineprefix volume, and you approve them in TavernKeeper. Two notes:
  `WHITELIST_ENABLED` **still does not gate joins** (the `users.json`
  whitelist does, case-sensitively — unchanged from 1.8.2), and an application
  is an unauthenticated claim of a name — **verify who it is out-of-band
  before whitelisting.**
- **Region tag.** The community browser now shows a region per server;
  servers that don't set one are labelled "unknown". Set `REGION_TAG` in
  `.env` (or set it once via TavernKeeper — the entrypoint preserves an
  existing value, same as the listing token).
- **`quest_scene`.** A new `server_settings.json` field, advertised to joining
  launchers, that switches the server to the Quest scene variant. The
  entrypoint preserves it (override with `QUEST_SCENE` in `.env`); fresh
  installs default to off. Leave it alone unless you know you want it.
- **Scheduled reboots** and the new **addons/macros system** are features of
  the Windows launcher apps (TavernLauncher / TavernKeeper), not of the
  headless server. Nothing to install here — the compose `restart:
  unless-stopped` plus a cron'd `docker compose restart` remains the headless
  equivalent of the reboot scheduler.

## The TavernLib version story, updated

1.8.2's advice was "you cannot pin TavernLib, only the launcher". That is no
longer true — TavernLib now publishes its own single-file release asset, and
the kit pins it directly. What *remains* true is that you cannot trust
self-reported versions or tags: the bundled v1.5.0 build self-reports an older
version string, and the v1.5.1 tag is identical to v1.5.0's — the fix exists
only in the rebuilt asset. Hence the sha256 pin: `TAVERNLIB_SHA256` is
pre-filled for the default `v1.5.1`, must be set (or deliberately blanked)
when you pin anything else, and a mismatch stops the patch rather than booting
a DLL nobody has vouched for.

## Firewall

**Unchanged.** Same table as 1.8.2:

| Port | State | Why |
|---|---|---|
| 1757 TCP+UDP | open | the game itself (voice rides this channel) |
| 1761 TCP | open | world/terrain cache download |
| 1762 TCP | **open** | the auth service — joins and now whitelist applications arrive here |
| 1760 TCP | **closed** | the WS console (TavernKeeper). Reach it over an SSH tunnel |
| 1763 | outbound only | community API |

## Still true from 1.8.2

- **`ENFORCE_IP_LIMIT` — leave it 0.** The counting bug is still there in
  v1.5.1: more than four accounts *in total* and every join is rejected.
- The join password recipe (double SHA-256) and its two traps — see
  [UPGRADE-1.8.2.md](UPGRADE-1.8.2.md).
- The two console credential files in the wineprefix volume, and the "treat
  the volume as a credential store" rule. `whitelist_requests.json` now lives
  there too.
