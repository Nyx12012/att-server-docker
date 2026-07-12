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
