#!/usr/bin/env bash
# Patch the mounted game folder the way TavernLauncher-Server's Patch + Mods
# buttons do on Windows: core Root.Township.dll patch, Plugins/TavernLib.dll,
# MelonLoader, and the voice mod — all extracted from ONE pinned TavernLauncher
# release zip (Modding Tavern's own released files; the game itself stays yours).
#
# Idempotent: .tavern-patch-version in the game folder records the applied
# release; if it matches the wanted version this is a no-op, so it's safe to run
# on every boot. That's what makes "git pull && docker compose up -d --build" a
# complete server upgrade — no Windows re-patch, no new game.zip upload.
#
# A clean base game folder (A Township Tale.exe + A Township Tale_Data/) is
# enough; an already-patched folder is fine too. Your own Mods/ are not touched
# (only Mods/CircuitsVoiceChat.dll, which belongs to the launcher).
set -euo pipefail

GAME_DIR="${GAME_DIR:-/game}"
WANT="${TAVERN_VERSION:-v1.8.1}"     # pinned; "latest" tracks upstream releases
STAMP="$GAME_DIR/.tavern-patch-version"
FORCE="${1:-}"

log(){ printf '[patcher] %s\n' "$*"; }
die(){ printf '[patcher] ERROR: %s\n' "$*" >&2; exit 1; }

MANAGED="$GAME_DIR/A Township Tale_Data/Managed"
[ -d "$MANAGED" ] || die "'$MANAGED' not found — the game folder must contain the base game (A Township Tale.exe + A Township Tale_Data/)."

# Resolve "latest" to a concrete tag via the GitHub release redirect.
if [ "$WANT" = "latest" ]; then
  WANT="$(curl -sfI -o /dev/null -w '%{redirect_url}' \
    "https://github.com/ModdingTavern/TavernLauncher/releases/latest" | sed 's|.*/||')"
  [ -n "$WANT" ] || die "could not resolve the latest TavernLauncher release (GitHub unreachable?). Pin TAVERN_VERSION or set AUTO_PATCH=0."
fi

HAVE=""
[ -f "$STAMP" ] && HAVE="$(cat "$STAMP")"
if [ "$FORCE" != "force" ] && [ "$HAVE" = "$WANT" ] \
   && [ -f "$GAME_DIR/Plugins/TavernLib.dll" ] && [ -f "$GAME_DIR/version.dll" ]; then
  log "game folder already patched for TavernLauncher $WANT"
  exit 0
fi

URL="https://github.com/ModdingTavern/TavernLauncher/releases/download/$WANT/TavernLauncher-Server-$WANT.zip"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log "downloading TavernLauncher $WANT server package…"
curl -sfL --retry 3 -o "$TMP/launcher.zip" "$URL" \
  || die "download failed: $URL — if GitHub is unreachable, set AUTO_PATCH=0 to boot with the files you have."
unzip -q -j -o "$TMP/launcher.zip" "*/Patch/*" -d "$TMP" 2>/dev/null \
  || unzip -q -j -o "$TMP/launcher.zip" "Patch/*" -d "$TMP" \
  || die "no Patch/ folder inside the release zip — upstream layout changed, not patching."

# Refuse to half-patch: a partial set of files is worse than the old version.
for f in themoddingtavern.dll TavernLib.dll MelonLoader.x64.zip Concentus.dll; do
  [ -f "$TMP/$f" ] || die "release zip is missing Patch/$f — upstream layout changed, not patching."
done
CVC="$(ls "$TMP"/CircuitsVoiceChat*.dll 2>/dev/null | head -1 || true)"

# MelonLoader first — a clean base game has none. The zip carries MelonLoader/
# and version.dll at its root, exactly as the launcher lays them down.
log "installing MelonLoader (the $WANT bundle)"
unzip -q -o "$TMP/MelonLoader.x64.zip" -d "$GAME_DIR"
[ -f "$GAME_DIR/version.dll" ] || die "MelonLoader bundle didn't produce version.dll — aborting before touching the game DLLs."

log "applying core patch (themoddingtavern.dll -> Managed/Root.Township.dll)"
cp -f "$TMP/themoddingtavern.dll" "$MANAGED/Root.Township.dll"

log "installing Plugins/TavernLib.dll"
mkdir -p "$GAME_DIR/Plugins"
cp -f "$TMP/TavernLib.dll" "$GAME_DIR/Plugins/TavernLib.dll"

# Voice: the launcher installs the versioned dll as plain CircuitsVoiceChat.dll
# (keeping the version suffix would stack old+new mods) + Concentus in UserLibs.
if [ -n "$CVC" ]; then
  log "installing voice ($(basename "$CVC") -> Mods/CircuitsVoiceChat.dll)"
  mkdir -p "$GAME_DIR/Mods" "$GAME_DIR/UserLibs"
  cp -f "$CVC" "$GAME_DIR/Mods/CircuitsVoiceChat.dll"
  cp -f "$TMP/Concentus.dll" "$GAME_DIR/UserLibs/Concentus.dll"
else
  log "WARNING: no CircuitsVoiceChat*.dll in this release — leaving voice files as they are"
fi

printf '%s\n' "$WANT" > "$STAMP"
log "done — game folder is on TavernLauncher $WANT (your own mods untouched)"
