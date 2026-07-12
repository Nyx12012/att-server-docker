#!/usr/bin/env bash
# TavernVoice relay installer — sets up ONLY the proximity-voice relay (NOT a game
# server) as a systemd service, opens the firewall, and starts it. One file, no repo
# clone, re-runnable. The relay is a tiny zero-dependency UDP forwarder; it must run on
# the SAME box (same public IP) as the ATT game server players connect to.
#
#   sudo bash install-relay.sh
#   sudo VOICE_PORT=1765 VOICE_RANGE=25 bash install-relay.sh
#
# After it finishes the relay is live and auto-starts on every reboot. Players only need
# the TavernVoice client mod; nothing else on the game server has to change.
set -euo pipefail

PORT="${VOICE_PORT:-1765}"
RANGE="${VOICE_RANGE:-25}"
DIR=/opt/att-voice
SVC=att-voice

# --- need root (for systemd, /opt, firewall) ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Elevating with sudo..."
  exec sudo -E VOICE_PORT="$PORT" VOICE_RANGE="$RANGE" bash "$0" "$@"
fi

echo "== TavernVoice relay installer =="
echo "   port=${PORT}/udp  range=${RANGE}m  dir=${DIR}  service=${SVC}"

# --- ensure Node.js (relay uses only core 'dgram', any recent Node works) ---
if ! command -v node >/dev/null 2>&1 && ! command -v nodejs >/dev/null 2>&1; then
  echo "-- Node.js not found; installing via the system package manager..."
  if   command -v apt-get >/dev/null 2>&1; then apt-get update -y && apt-get install -y nodejs
  elif command -v dnf     >/dev/null 2>&1; then dnf install -y nodejs
  elif command -v yum     >/dev/null 2>&1; then yum install -y nodejs
  elif command -v pacman  >/dev/null 2>&1; then pacman -Sy --noconfirm nodejs
  elif command -v zypper  >/dev/null 2>&1; then zypper install -y nodejs
  elif command -v apk     >/dev/null 2>&1; then apk add --no-cache nodejs
  else echo "!! Could not auto-install Node.js. Install 'nodejs' manually, then re-run."; exit 1
  fi
fi
NODE="$(command -v node || command -v nodejs || true)"
if [ -z "$NODE" ]; then echo "!! Node.js still not found after install."; exit 1; fi
echo "-- node: ${NODE} ($("$NODE" --version 2>/dev/null))"

# --- write the relay (embedded verbatim) ---
mkdir -p "$DIR"
cat > "$DIR/relay.js" <<'RELAYEOF'
// TavernVoice relay — self-hosted proximity (positional) voice for A Township Tale.
//
// Clients send small UDP datagrams carrying a header {version, type, senderId,
// x, y, z, seq} followed by an opaque Opus payload. This relay reads ONLY the
// header: it tracks where each speaker is, then forwards each voice datagram —
// byte for byte, payload untouched — to the other players within range. It never
// decodes audio, so it needs no codec and stays tiny. Zero npm dependencies.
//
// One relay per server. Auto-starts with the stack (docker compose). Clients
// discover it by convention on VOICE_PORT of the same box they joined, so a
// single client mod works on every server running this.
'use strict';

const dgram = require('dgram');

const PORT      = parseInt(process.env.VOICE_PORT || '1765', 10);
const RANGE     = parseFloat(process.env.VOICE_RANGE || '30');   // metres, hard cutoff
const RANGE_SQ  = RANGE * RANGE;
const PEER_TTL  = parseInt(process.env.VOICE_PEER_TTL_MS || '12000', 10); // drop silent/gone peers
const MAX_PPS   = parseInt(process.env.VOICE_MAX_PPS || '400', 10);       // per-source packet/sec cap
const DEBUG     = process.env.VOICE_DEBUG === '1';

// Wire format (little-endian). Header is 20 bytes; payload follows.
const VERSION    = 1;
const HDR        = 20;
const T_KEEPALIVE = 0; // position/endpoint refresh, no audio, not forwarded
const T_VOICE     = 1; // header + Opus payload, forwarded to in-range peers
const T_BYE       = 2; // sender leaving, drop from table

// senderId -> { addr, port, x, y, z, last }
const peers = new Map();
// source "ip:port" -> { count, windowStart } for a cheap flood cap
const rate = new Map();

const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });

function now() { return Date.now(); }

function rateOk(key) {
  const t = now();
  let r = rate.get(key);
  if (!r || t - r.windowStart >= 1000) { r = { count: 0, windowStart: t }; rate.set(key, r); }
  r.count++;
  return r.count <= MAX_PPS;
}

sock.on('message', (msg, rinfo) => {
  if (msg.length < HDR) return;                 // too short to be ours
  if (msg.readUInt8(0) !== VERSION) return;     // stale/foreign client — fail clean

  const srcKey = rinfo.address + ':' + rinfo.port;
  if (!rateOk(srcKey)) return;

  const type     = msg.readUInt8(1);
  const senderId = msg.readUInt32LE(2);
  const x = msg.readFloatLE(6);
  const y = msg.readFloatLE(10);
  const z = msg.readFloatLE(14);
  if (!isFinite(x) || !isFinite(y) || !isFinite(z)) return;

  if (type === T_BYE) {
    peers.delete(senderId);
    if (DEBUG) console.log('[relay] bye', senderId);
    return;
  }

  // Refresh this speaker's endpoint + position on every packet (handles NAT
  // rebinds and movement). Keyed by the stable per-session network id.
  peers.set(senderId, { addr: rinfo.address, port: rinfo.port, x, y, z, last: now() });

  if (type !== T_VOICE) return;                 // keepalive: position only, nothing to forward

  // Forward the whole datagram (header carries senderId + position the receiver
  // needs to place the voice in-world) to every OTHER peer within range.
  let sent = 0;
  for (const [id, p] of peers) {
    if (id === senderId) continue;
    const dx = p.x - x, dy = p.y - y, dz = p.z - z;
    if (dx * dx + dy * dy + dz * dz > RANGE_SQ) continue;
    sock.send(msg, p.port, p.addr);
    sent++;
  }
  if (DEBUG && sent) console.log('[relay] voice', senderId, '->', sent, 'peer(s)', msg.length + 'B');
});

// Reap peers we haven't heard from (left, crashed, or went silent without a bye).
setInterval(() => {
  const cutoff = now() - PEER_TTL;
  for (const [id, p] of peers) if (p.last < cutoff) peers.delete(id);
  if (rate.size > 4096) rate.clear();
}, 5000).unref();

sock.on('error', (err) => { console.error('[relay] socket error:', err.message); });

sock.bind(PORT, '0.0.0.0', () => {
  console.log(`[relay] TavernVoice up on udp/${PORT}  range=${RANGE}m  ttl=${PEER_TTL}ms`);
});

// Clean shutdown for `docker stop`.
function shutdown() { try { sock.close(); } catch (e) {} process.exit(0); }
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
RELAYEOF
echo "-- wrote ${DIR}/relay.js"

# --- systemd service (auto-restart, starts on boot, sandboxed non-root user) ---
cat > "/etc/systemd/system/${SVC}.service" <<UNITEOF
[Unit]
Description=TavernVoice proximity-voice relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=VOICE_PORT=${PORT}
Environment=VOICE_RANGE=${RANGE}
ExecStart=${NODE} ${DIR}/relay.js
Restart=always
RestartSec=3
DynamicUser=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
UNITEOF
echo "-- wrote /etc/systemd/system/${SVC}.service"

systemctl daemon-reload
systemctl enable "$SVC" >/dev/null 2>&1 || true
systemctl restart "$SVC"
sleep 1

# --- firewall (best effort for ufw / firewalld) ---
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PORT}/udp" >/dev/null 2>&1 && echo "-- ufw: allowed ${PORT}/udp" || true
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${PORT}/udp" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 && echo "-- firewalld: allowed ${PORT}/udp" || true
fi

# --- report ---
echo
if systemctl is-active --quiet "$SVC"; then
  echo "OK — relay is RUNNING on ${PORT}/udp and will start on every reboot."
else
  echo "!! Service did not report active. Check: journalctl -u ${SVC} -e"
fi
command -v ss >/dev/null 2>&1 && ss -ulnp 2>/dev/null | grep ":${PORT} " >/dev/null 2>&1 && echo "-- confirmed: something is listening on udp/${PORT}"
echo
echo "  status:  systemctl status ${SVC}"
echo "  logs:    journalctl -u ${SVC} -f"
echo "  stop:    systemctl stop ${SVC}     (disable boot: systemctl disable ${SVC})"
echo
echo "IMPORTANT:"
echo "  * If your host has a CLOUD firewall (provider panel / security group),"
echo "    also allow ${PORT}/udp there — the OS firewall above isn't enough on its own."
echo "  * The relay must be reachable at the SAME public IP as your game server."
echo "  * Players just install the TavernVoice client mod; no game-server restart needed."
