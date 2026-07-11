#!/bin/sh
# Community heartbeat — this is what lets friends join by typing your IP into the
# stock TavernLauncher, with no per-friend files.
#
# Every 30s it POSTs your server to the Modding Tavern community backend as a
# "headless" server. When a friend types your IP, their launcher fails the auth
# pre-flight on :1762 (a headless server never answers there), then asks the
# backend "is <IP> a known headless server?" — this heartbeat is what makes the
# answer yes, so the launcher joins directly (no auth handshake).
#
# Runs in a tiny container that shares the host network, so the POST's source IP
# is your real public IPv4 (via curl -4). The backend keys the listing on that
# source IP + the port below.
set -eu

: "${SERVER_NAME:?set SERVER_NAME in .env}"
: "${LISTING_TOKEN:?set LISTING_TOKEN in .env (any long random string, unique to you)}"

HOST="${COMMUNITY_HOST:-themoddingtavern.com}"
PORT="${SERVER_PORT:-1757}"
LIMIT="${MAX_PLAYERS:-8}"

echo "[register] listing '$SERVER_NAME' on port $PORT -> $HOST:1763 (every 30s)"

while true; do
  # -4 is REQUIRED: many VPSes default to IPv6 outbound; without it the backend
  # records the wrong (IPv6) address and friends typing the IPv4 won't match.
  code=$(curl -4 -s -o /dev/null -w '%{http_code}' \
    -X POST "http://$HOST:1763/servers" \
    -H 'Content-Type: application/json' \
    -d "{\"listing_token\":\"$LISTING_TOKEN\",\"name\":\"$SERVER_NAME\",\"port\":$PORT,\"player_limit\":$LIMIT,\"has_password\":false,\"kind\":\"headless\"}" \
    2>/dev/null || echo "000")
  [ "$code" = "200" ] || echo "[register] POST returned $code — will retry in 30s"
  sleep 30
done
