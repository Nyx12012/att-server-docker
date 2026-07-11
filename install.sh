#!/usr/bin/env bash
# One-command installer for the A Township Tale headless server (Docker + Wine).
#
# Usage (from a clone):        ./install.sh [/path/to/game]
# Usage (bootstrap, no clone): curl -fsSL https://raw.githubusercontent.com/Nyx12012/att-server-docker/main/install.sh | bash
#
# It will: install Docker if missing, fetch this repo if run standalone, create
# .env, obtain the game files (via GAME_URL or the ./game folder you provide),
# then build and start the container.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Nyx12012/att-server-docker.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/att-server-docker}"

log(){ printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[install] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

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

# --- 3. .env -----------------------------------------------------------------
[ -f .env ] || { cp .env.example .env; log "Created .env from template."; }
# shellcheck disable=SC1091
set -a; . ./.env; set +a

# --- 4. Game files -----------------------------------------------------------
GAME_ARG="${1:-}"
if [ -n "$GAME_ARG" ]; then
  # explicit path passed -> point .env at it
  sed -i "s#^ATT_GAME_DIR=.*#ATT_GAME_DIR=${GAME_ARG//#/\\#}#" .env
  ATT_GAME_DIR="$GAME_ARG"
fi
ATT_GAME_DIR="${ATT_GAME_DIR:-./game}"

if [ ! -f "$ATT_GAME_DIR/A Township Tale.exe" ]; then
  if [ -n "${GAME_URL:-}" ]; then
    log "Downloading game files from GAME_URL…"
    mkdir -p ./game
    tmp="$(mktemp)"; curl -fL "$GAME_URL" -o "$tmp"
    case "$GAME_URL" in
      *.zip)            unzip -q -o "$tmp" -d ./game ;;
      *.tar.gz|*.tgz)   tar -xzf "$tmp" -C ./game ;;
      *) die "GAME_URL must end in .zip, .tar.gz, or .tgz" ;;
    esac
    rm -f "$tmp"
    # if the archive nested a top folder, flatten so the exe is at ./game/
    if [ ! -f "./game/A Township Tale.exe" ]; then
      inner="$(find ./game -maxdepth 2 -name 'A Township Tale.exe' -printf '%h\n' | head -1 || true)"
      [ -n "$inner" ] && { shopt -s dotglob; mv "$inner"/* ./game/ 2>/dev/null || true; shopt -u dotglob; }
    fi
    ATT_GAME_DIR="./game"
  else
    die "No game files. Put your patched 'A Township Tale' folder at '$ATT_GAME_DIR' \
(so '$ATT_GAME_DIR/A Township Tale.exe' exists), or set GAME_URL in .env, then re-run."
  fi
fi
log "Game files OK at: $ATT_GAME_DIR"

# --- 5. Build + run ----------------------------------------------------------
log "Building image (first run pulls Wine — takes a few minutes)…"
docker compose build
log "Starting server…"
docker compose up -d

cat <<EOF

\033[1;32m[install] Server is starting.\033[0m
  Logs:     docker compose logs -f
  Stop:     docker compose down
  Restart:  docker compose up -d

Watch the logs for TavernLib loading and 'Running web server'. Then point a
patched client at this host on UDP/TCP 1757. See README.md for testing details.
EOF
