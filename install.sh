#!/usr/bin/env bash
# One-command installer for the A Township Tale headless server (Docker + Wine).
# You supply your OWN patched game files — this kit ships no game binaries.
#
# Usage (from a clone):        ./install.sh [/path/to/patched/game]
# Usage (bootstrap, no clone): curl -fsSL https://raw.githubusercontent.com/Nyx12012/att-server-docker/main/install.sh | bash
#
# It installs Docker if missing, fetches this repo if run standalone, creates
# .env (with a random per-server LISTING_TOKEN), finds your game files, opens the
# firewall, then starts the server + the join-by-IP registration heartbeat.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Nyx12012/att-server-docker.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/att-server-docker}"

log(){ printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[install] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

gen_token(){
  if have openssl; then openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-43
  else head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-43; fi
}

# If an archive unpacked with a top-level folder, move the game up so the exe
# sits directly in ./game.
flatten_game(){
  [ -f "./game/A Township Tale.exe" ] && return 0
  local inner
  inner="$(find ./game -maxdepth 3 -name 'A Township Tale.exe' -printf '%h\n' 2>/dev/null | head -1 || true)"
  if [ -n "$inner" ] && [ "$inner" != "./game" ]; then
    log "Flattening nested game folder: $inner -> ./game"
    shopt -s dotglob; mv "$inner"/* ./game/ 2>/dev/null || true; shopt -u dotglob
  fi
}

configure_firewall(){
  [ "${SKIP_UFW:-0}" = "1" ] && { log "SKIP_UFW=1 — leaving the firewall alone."; return 0; }
  have ufw || { log "ufw not found — skipping firewall. Make sure your provider allows inbound 1757 (TCP+UDP), 1761 (TCP), and 1762 (TCP — the auth service lives there now)."; return 0; }
  local S=""; [ "$(id -u)" -ne 0 ] && S="sudo"
  log "Opening firewall (SSH first, so you can't lock yourself out)…"
  $S ufw allow 22/tcp    >/dev/null 2>&1 || true   # SSH — always allow first
  $S ufw allow 1757/tcp  >/dev/null 2>&1 || true   # game handshake
  $S ufw allow 1757/udp  >/dev/null 2>&1 || true   # game traffic (KCP)
  $S ufw allow 1761/tcp  >/dev/null 2>&1 || true   # world/terrain cache download
  # Since v1.8.1 the server RUNS a real auth service on 1762 (TavernLib) and the
  # launcher must reach it to join — this is no longer the "allowed-but-refused
  # probe" trick, it's a live listener that must be open.
  $S ufw allow 1762/tcp  >/dev/null 2>&1 || true
  $S ufw --force enable   >/dev/null 2>&1 || true
  $S ufw reload           >/dev/null 2>&1 || true
  log "Firewall: 22, 1757/tcp+udp, 1761/tcp, 1762/tcp(auth) open; 1763/1764 stay closed."
  # Voice (CircuitsVoiceChat) rides the game channel — no extra port to open.
}

# --- 1. Docker ---------------------------------------------------------------
if ! have docker; then
  log "Docker not found — installing via get.docker.com (needs sudo)…"
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  log "Docker installed. You may need to log out/in for group changes."
fi
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin missing. Install 'docker-compose-plugin'."

# --- 2. Get the repo (if this script was piped in standalone) ----------------
if [ -f "docker-compose.yml" ] && [ -f "Dockerfile" ]; then
  REPO_DIR="$(pwd)"                       # already inside a clone
else
  have git || die "git not found; install git or clone the repo manually."
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "Cloning $REPO_URL -> $INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  else
    log "Updating existing clone at $INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only || true
  fi
  REPO_DIR="$INSTALL_DIR"
fi
cd "$REPO_DIR"

# --- 3. .env + a private per-server listing token ----------------------------
[ -f .env ] || { cp .env.example .env; log "Created .env from template."; }
# Generate a unique LISTING_TOKEN the first time (only if still blank).
if grep -qE '^LISTING_TOKEN=$' .env; then
  TOK="$(gen_token)"
  sed -i "s#^LISTING_TOKEN=.*#LISTING_TOKEN=${TOK}#" .env
  log "Generated a private LISTING_TOKEN for this server."
fi
# Read only what the installer itself needs. Do NOT `source` .env — it's a compose
# env file, and values like SERVER_NAME contain spaces (sourcing would break under
# set -e). Compose reads .env directly for the container's environment.
ATT_GAME_DIR="$(grep -E '^ATT_GAME_DIR=' .env | cut -d= -f2- || true)"
GAME_URL="$(grep -E '^GAME_URL=' .env | cut -d= -f2- || true)"

# --- 4. Game files (you supply them; the kit ships none) ---------------------
GAME_ARG="${1:-}"
if [ -n "$GAME_ARG" ]; then
  # explicit path passed -> point .env at it
  sed -i "s#^ATT_GAME_DIR=.*#ATT_GAME_DIR=${GAME_ARG//#/\\#}#" .env
  ATT_GAME_DIR="$GAME_ARG"
fi
ATT_GAME_DIR="${ATT_GAME_DIR:-./game}"

if [ ! -f "$ATT_GAME_DIR/A Township Tale.exe" ]; then
  # Source priority: a game.zip you uploaded here > a GAME_URL you host > stop.
  LOCAL_ARCHIVE=""
  for z in "$REPO_DIR"/game.zip "$REPO_DIR"/game.tar.gz "$REPO_DIR"/game.tgz; do
    [ -f "$z" ] && { LOCAL_ARCHIVE="$z"; break; }
  done
  if [ -n "$LOCAL_ARCHIVE" ]; then
    log "Found $(basename "$LOCAL_ARCHIVE") — extracting into ./game …"
    mkdir -p ./game
    case "$LOCAL_ARCHIVE" in
      *.zip)          have unzip || die "unzip not installed (run: apt-get install -y unzip)."; unzip -q -o "$LOCAL_ARCHIVE" -d ./game ;;
      *.tar.gz|*.tgz) tar -xzf "$LOCAL_ARCHIVE" -C ./game ;;
    esac
    flatten_game
    ATT_GAME_DIR="./game"
  elif [ -n "${GAME_URL:-}" ]; then
    log "Downloading game files from GAME_URL…"
    mkdir -p ./game
    tmp="$(mktemp)"; curl -fL "$GAME_URL" -o "$tmp"
    case "$GAME_URL" in
      *.zip)          unzip -q -o "$tmp" -d ./game ;;
      *.tar.gz|*.tgz) tar -xzf "$tmp" -C ./game ;;
      *) rm -f "$tmp"; die "GAME_URL must end in .zip, .tar.gz, or .tgz" ;;
    esac
    rm -f "$tmp"
    flatten_game
    ATT_GAME_DIR="./game"
  else
    die "No game files yet. Upload YOUR patched server folder as a zip to \
'$REPO_DIR/game.zip' (or put the folder at '$ATT_GAME_DIR' so '$ATT_GAME_DIR/A Township Tale.exe' \
exists, or set GAME_URL in .env), then run ./install.sh again. See SETUP-GUIDE.md."
  fi
fi
[ -f "$ATT_GAME_DIR/version.dll" ] || log "WARNING: no version.dll in the game folder — is it actually patched (MelonLoader)? Mods won't load without it."
log "Game files OK at: $ATT_GAME_DIR"

# --- 5. Firewall -------------------------------------------------------------
configure_firewall

# --- 6. Build + run ----------------------------------------------------------
log "Building image (first run pulls Wine — a few minutes)…"
docker compose build
log "Starting server (native community listing from server_settings.json)…"
docker compose up -d

G=$'\033[1;32m'; N=$'\033[0m'
NAME_SHOWN="$(grep -E '^SERVER_NAME=' .env | cut -d= -f2- || true)"
PUBIP="$(curl -4 -fsS https://ifconfig.me 2>/dev/null || echo 'YOUR.VPS.IP')"
cat <<EOF

${G}[install] Done — your server is starting.${N}
  Name friends will see:               ${NAME_SHOWN:-My Township Server}
  Join address (give this to friends): ${PUBIP}

  Logs:     docker compose logs -f
  Stop:     docker compose down
  Restart:  docker compose up -d

Friends join by patching their OWN game with TavernLauncher (Client) — v1.8.1 or
newer — typing ${PUBIP} into the launcher, and hitting Join. On first join the
launcher registers their username with YOUR server (the new 1762 auth service);
no files to hand out. See SETUP-GUIDE.md → "How your friends join".

In 'docker compose logs -f' look for: "Melon Assembly loaded: 'Plugins/TavernLib.dll'"
and the world loading.

Check your community listing points at THIS box's IPv4:
  curl "http://${COMMUNITY_HOST:-themoddingtavern.com}:1763/servers/lookup?address=${PUBIP}"
Expect {"found":true,...}. If it's not found, turn on the IPv4 heartbeat
fallback:  docker compose --profile fallback up -d
See UPGRADE-1.8.1.md for the full listing walkthrough.
EOF
