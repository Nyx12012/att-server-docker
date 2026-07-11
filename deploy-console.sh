#!/usr/bin/env bash
# Deploy the TavernConsole admin console into the running ATT headless server.
#
# WHY PORT 1764 (READ THIS): the console binds a web server on whatever
# console_port.txt says (default 1762). 1762 is ALSO the port the stock
# TavernLauncher probes for an "official auth service" before it falls back to
# the community lookup that lets friends join by IP. That probe MUST get
# connection-refused on 1762 or the fallback (and thus joining) can break.
# So we run the console on 1764 and NEVER open 1764 in ufw — it stays
# loopback-reachable for a same-box Discord bot only. Do not `ufw allow 1764`.
#
# Prereq: stage the two artifacts from the Windows archive into
#   ~/att-server-docker/console-deploy/
#     TavernConsole.dll
#     att_console/            (the whole UserData\att_console folder: trusted/, cli/, allowlist.txt, ...)
# e.g. from the Windows box:
#   scp "C:\Games\Alta\_ATT_ours_archive\mods\TavernConsole.dll" root@144.126.133.142:~/att-server-docker/console-deploy/
#   scp -r "C:\Games\Alta\_ATT_ours_archive\userdata\att_console" root@144.126.133.142:~/att-server-docker/console-deploy/
set -euo pipefail

REPO="$HOME/att-server-docker"
GAME="$REPO/game"
STAGE="$REPO/console-deploy"
PORT=1764

[ -f "$STAGE/TavernConsole.dll" ] || { echo "MISSING: $STAGE/TavernConsole.dll (scp it first)"; exit 1; }
[ -d "$STAGE/att_console" ]       || { echo "MISSING: $STAGE/att_console/ (scp it first)"; exit 1; }
[ -d "$GAME/Mods" ]               || { echo "MISSING: $GAME/Mods — is the game folder populated?"; exit 1; }

echo "[1/4] placing TavernConsole.dll into game/Mods"
cp "$STAGE/TavernConsole.dll" "$GAME/Mods/TavernConsole.dll"

echo "[2/4] placing UserData/att_console"
mkdir -p "$GAME/UserData"
cp -r "$STAGE/att_console" "$GAME/UserData/att_console"

echo "[3/4] pinning console port to $PORT (off the 1762 launcher-probe port)"
echo -n "$PORT" > "$GAME/UserData/att_console/console_port.txt"

echo "[4/4] restarting container"
cd "$REPO"
docker compose restart att-server

echo
echo "Done. Verify with:"
echo "  docker logs att-server 2>&1 | grep -iE 'Dedicated console server|Secure console auth|Command modules'"
echo "Expect: 'Dedicated console server on port $PORT' + 'Secure console auth active'."
echo
echo "SANITY (join flow must stay intact): 1762 must still be REFUSED from outside."
echo "  From another machine: curl --connect-timeout 5 http://144.126.133.142:1762/  -> should fail (exit 7)."
echo "Do NOT run 'ufw allow $PORT'. The console is loopback-only for the bot."
