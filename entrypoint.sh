#!/usr/bin/env bash
# Boot the ATT server headless under Wine. Mirrors startServer.bat from the
# Windows install, plus -nographics and container-friendly signal handling.
set -euo pipefail

GAME_DIR="${GAME_DIR:-/game}"
GAME_EXE="${GAME_EXE:-A Township Tale.exe}"
INSTANCE_ID="${INSTANCE_ID:--1}"
SERVER_PORT="${SERVER_PORT:-1757}"
PATCHER="${PATCHER:-/patcher.sh}"
export GAME_DIR

# One-shot re-patch (server stopped): docker compose run --rm att-server update
if [ "${1:-}" = "update" ]; then
  "$PATCHER" force
  echo "[entrypoint] update complete — start normally with: docker compose up -d"
  exit 0
fi

: "${ATT_ACCESS_TOKEN:?set ATT_ACCESS_TOKEN in .env}"
: "${ATT_REFRESH_TOKEN:?set ATT_REFRESH_TOKEN in .env}"
: "${ATT_IDENTITY_TOKEN:?set ATT_IDENTITY_TOKEN in .env}"

echo "[entrypoint] game dir: $GAME_DIR  instance: $INSTANCE_ID  port: $SERVER_PORT"
if [ ! -f "$GAME_DIR/$GAME_EXE" ]; then
  echo "[entrypoint] ERROR: '$GAME_DIR/$GAME_EXE' not found. Did you mount your game folder to $GAME_DIR? See README." >&2
  exit 1
fi

# Keep the game folder on the pinned TavernLauncher release (no-op when already
# current). This is what makes `git pull && docker compose up -d --build` a full
# upgrade. AUTO_PATCH=0 boots with whatever is in the folder (hand-patched setups).
if [ "${AUTO_PATCH:-1}" = "1" ]; then
  "$PATCHER"
else
  echo "[entrypoint] AUTO_PATCH=0 — skipping patch check"
fi
if [ ! -f "$GAME_DIR/version.dll" ]; then
  echo "[entrypoint] WARNING: $GAME_DIR/version.dll missing — MelonLoader won't inject. Is this folder actually patched?" >&2
fi

# --- server_settings.json / tavern_server.json (v1.8.1 / TavernLib v1.3) ------
# v1.8.1 dropped server-config.yaml entirely (YamlDotNet removed). TavernLib now
# reads JSON from the Wine user's AppData:
#   …/TheModdingTavern/server_settings.json  name, listing, whitelist, password
#   …/TheModdingTavern/tavern_server.json    server_port
# The same folder also holds users.json — the accounts friends register through
# the NEW auth service the server runs on TCP 1762. It all sits inside the
# wineprefix volume, so accounts and settings survive restarts/rebuilds.
# We regenerate the managed fields every boot so .env stays the single source of
# truth; the community_listing_token and password_hash already in the file are
# preserved (TavernLib auto-generates a token if it's blank). Set
# WRITE_SERVER_CONFIG=0 to leave hand-tuned files alone.
if [ "${WRITE_SERVER_CONFIG:-1}" = "1" ]; then
  tav_dir="${TAVERN_DIR:-}"
  if [ -z "$tav_dir" ]; then
    for u in /wine/drive_c/users/*/AppData/Roaming; do
      [ -d "$u" ] && tav_dir="$u/TheModdingTavern" && break
    done
  fi
  tav_dir="${tav_dir:-/wine/drive_c/users/root/AppData/Roaming/TheModdingTavern}"
  mkdir -p "$tav_dir"
  cfg="$tav_dir/server_settings.json"

  jesc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  # `|| true` matters: set -o pipefail would otherwise turn "field not found"
  # (grep status 1) into a fatal boot error.
  jget(){ grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//' || true; }

  # Keep what TavernLib (or the owner) already stored unless .env overrides it.
  tok="${LISTING_TOKEN:-}";        [ -z "$tok" ] && [ -f "$cfg" ] && tok="$(jget "$cfg" community_listing_token)"
  pwh="${SERVER_PASSWORD_HASH:-}"; [ -z "$pwh" ] && [ -f "$cfg" ] && pwh="$(jget "$cfg" password_hash)"

  # Listed unless told otherwise. (Old kit semantics: token present = listed.)
  listed="${COMMUNITY_LISTED:-}"
  [ -z "$listed" ] && { [ -n "${LISTING_TOKEN:-}" ] && listed=1 || listed=0; }
  case "$listed" in 1|true|yes) listed=true ;; *) listed=false ;; esac

  # The listing's hostname is the address friends' launchers use from the community
  # browser — it MUST be a bare IP/host, never a web page. Auto-detect our public
  # IPv4 from IP-only endpoints (ifconfig.me's ROOT serves wget a full HTML page —
  # that once leaked into the listing), take the first line, and reject anything
  # that isn't host-shaped so we advertise a clean value or nothing at all.
  pub="${PUBLIC_HOSTNAME:-}"
  if [ -z "$pub" ]; then
    for _u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com https://checkip.amazonaws.com; do
      pub="$(curl -4 -fsS --max-time 5 "$_u" 2>/dev/null | head -n1 | tr -d '[:space:]')"
      case "$pub" in
        "" | *[!A-Za-z0-9.:-]* ) pub="" ;;   # empty or non-host chars (HTML/spaces) -> reject
        * ) break ;;                          # a bare IP/hostname -> keep it
      esac
    done
  fi

  {
    echo "{"
    echo "  \"name\": \"$(jesc "${SERVER_NAME:-My Township Server}")\","
    echo "  \"password_hash\": \"$(jesc "$pwh")\","
    echo "  \"whitelist_enabled\": $( [ "${WHITELIST_ENABLED:-0}" = "1" ] && echo true || echo false ),"
    echo "  \"enforce_ip_limit\": $( [ "${ENFORCE_IP_LIMIT:-0}" = "1" ] && echo true || echo false ),"
    echo "  \"community_listed\": $listed,"
    echo "  \"max_players\": ${MAX_PLAYERS:-8},"
    echo "  \"community_listing_token\": \"$(jesc "$tok")\","
    echo "  \"public_hostname\": \"$(jesc "$pub")\""
    echo "}"
  } > "$cfg"
  printf '{\n  "server_port": %s\n}\n' "${SERVER_PORT:-1757}" > "$tav_dir/tavern_server.json"

  # The old yaml is dead config on v1.8.1 — remove it so nobody edits it expecting effect.
  rm -f "$GAME_DIR/server-config.yaml"

  [ "$listed" = "true" ] && adv="listed" || adv="unlisted"
  echo "[entrypoint] wrote server_settings.json (name='${SERVER_NAME:-My Township Server}', $adv, public_hostname='${pub:-unset}') + tavern_server.json (port ${SERVER_PORT:-1757})"
fi

# Debug/test knob: write the configs and stop before touching Xvfb/Wine.
if [ "${CONFIG_ONLY:-0}" = "1" ]; then
  echo "[entrypoint] CONFIG_ONLY=1 — configs written, not launching the server."
  exit 0
fi

# --- virtual display ---------------------------------------------------------
mkdir -p "$XDG_RUNTIME_DIR"
Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 20); do [ -e /tmp/.X11-unix/X0 ] && break; sleep 0.5; done

# Don't pop a Wine crash dialog in a headless box.
wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

cd "$GAME_DIR"

echo "[entrypoint] launching server..."
# shellcheck disable=SC2086
wine "$GAME_EXE" -batchmode -nographics \
  /start_server "$INSTANCE_ID" false "$SERVER_PORT" \
  /debug_helper /force_offline \
  /access_token "$ATT_ACCESS_TOKEN" \
  /refresh_token "$ATT_REFRESH_TOKEN" \
  /identity_token "$ATT_IDENTITY_TOKEN" \
  --melonloader.hideconsole &
WINE_PID=$!

# Forward container stop -> graceful wine shutdown.
term() {
  echo "[entrypoint] SIGTERM -> stopping server..."
  kill -TERM "$WINE_PID" 2>/dev/null || true
  wineserver -k 2>/dev/null || true
}
trap term SIGTERM SIGINT

# Stream MelonLoader + server logs to container stdout once they appear.
( for _ in $(seq 1 60); do [ -f "$GAME_DIR/MelonLoader/Latest.log" ] && break; sleep 1; done
  tail -n +1 -F "$GAME_DIR/MelonLoader/Latest.log" 2>/dev/null ) &
TAIL_PID=$!

wait "$WINE_PID"
CODE=$?
kill "$TAIL_PID" "$XVFB_PID" 2>/dev/null || true
echo "[entrypoint] server exited with code $CODE"
exit $CODE
