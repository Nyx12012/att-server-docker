#!/bin/sh
# Community heartbeat — FALLBACK only on v1.8.1 (run via --profile fallback).
#
# TavernLib v1.3 registers the server itself every ~3s, and its payload carries a
# `hostname` field the entrypoint fills with your IPv4 — so the old "VPS registers
# over IPv6, friends type the IPv4" mismatch should be gone. Keep this around for
# the case where the native listing still doesn't resolve to your IPv4: it
# re-POSTs the listing forced over IPv4 (curl -4) with the same payload shape
# TavernLib v1.3 sends.
set -eu

: "${SERVER_NAME:?set SERVER_NAME in .env}"
: "${LISTING_TOKEN:?set LISTING_TOKEN in .env (any long random string, unique to you)}"

HOST="${COMMUNITY_HOST:-themoddingtavern.com}"
PORT="${SERVER_PORT:-1757}"
LIMIT="${MAX_PLAYERS:-8}"

# -4 is REQUIRED throughout: many VPSes default to IPv6 outbound; without it the
# backend records the wrong (IPv6) address and friends typing the IPv4 won't match.
PUB="${PUBLIC_HOSTNAME:-$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)}"

echo "[register] listing '$SERVER_NAME' ($PUB:$PORT) -> $HOST:1763 (every 15s)"

while true; do
  code=$(curl -4 -s -o /dev/null -w '%{http_code}' \
    -X POST "http://$HOST:1763/servers" \
    -H 'Content-Type: application/json' \
    -d "{\"listing_token\":\"$LISTING_TOKEN\",\"name\":\"$SERVER_NAME\",\"port\":$PORT,\"player_limit\":$LIMIT,\"has_password\":false,\"player_count\":0,\"community_listed\":true,\"hostname\":\"$PUB\"}" \
    2>/dev/null || echo "000")
  [ "$code" = "200" ] || echo "[register] POST returned $code — will retry in 15s"
  # v1.3 servers heartbeat every ~3s; the backend TTL may have shrunk to match,
  # so we post more often than the old 30s.
  sleep 15
done
