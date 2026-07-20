#!/usr/bin/env bash
# Boot the ATT server headless under Wine. Mirrors startServer.bat from the
# Windows install, plus -nographics and container-friendly signal handling.
set -euo pipefail

GAME_DIR="${GAME_DIR:-/game}"
GAME_EXE="${GAME_EXE:-A Township Tale.exe}"
INSTANCE_ID="${INSTANCE_ID:--1}"
SERVER_PORT="${SERVER_PORT:-1757}"

: "${ATT_ACCESS_TOKEN:?set ATT_ACCESS_TOKEN in .env}"
: "${ATT_REFRESH_TOKEN:?set ATT_REFRESH_TOKEN in .env}"
: "${ATT_IDENTITY_TOKEN:?set ATT_IDENTITY_TOKEN in .env}"

echo "[entrypoint] game dir: $GAME_DIR  instance: $INSTANCE_ID  port: $SERVER_PORT"
if [ ! -f "$GAME_DIR/$GAME_EXE" ]; then
  echo "[entrypoint] ERROR: '$GAME_DIR/$GAME_EXE' not found. Did you mount your patched game folder to $GAME_DIR? See README." >&2
  exit 1
fi
if [ ! -f "$GAME_DIR/version.dll" ]; then
  echo "[entrypoint] WARNING: $GAME_DIR/version.dll missing — MelonLoader won't inject. Is this folder actually patched?" >&2
fi

# --- server-config.yaml (name / description / native community listing) ------
# TavernLib reads <game>/server-config.yaml at boot. Writing it from .env is what
# gives friends a NAME + DESCRIPTION in the community list and lets v1.8.0
# advertise the server itself (native listing) — no sidecar needed. We regenerate
# it every boot so .env stays the single source of truth. Set WRITE_SERVER_CONFIG=0
# to leave a hand-tuned file alone, or if native registration misbehaves and you'd
# rather rely on the curl -4 heartbeat fallback (see UPGRADE-1.8.0.md).
if [ "${WRITE_SERVER_CONFIG:-1}" = "1" ]; then
  cfg="$GAME_DIR/server-config.yaml"
  yq_name=$(printf '%s' "${SERVER_NAME:-My Township Server}" | sed 's/"/\\"/g')
  yq_desc=$(printf '%s' "${SERVER_DESCRIPTION:-}" | sed 's/"/\\"/g')
  {
    echo "name: \"$yq_name\""
    echo "description: \"$yq_desc\""
    echo "max-players: ${MAX_PLAYERS:-8}"
    echo "pc-world: false"
    # listing-token present => TavernLib advertises to the community list.
    # Omit it (leave LISTING_TOKEN blank in .env) to run unlisted / direct-IP only.
    if [ -n "${LISTING_TOKEN:-}" ]; then echo "listing-token: \"$LISTING_TOKEN\""; fi
    echo "ports:"
    echo "  game: ${SERVER_PORT:-1757}"
    echo "  forest: 1761"
    echo "  rcon: 1762"
  } > "$cfg"
  if [ -n "${LISTING_TOKEN:-}" ]; then adv="listed"; else adv="unlisted"; fi
  echo "[entrypoint] wrote server-config.yaml (name='$yq_name', $adv)"
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
