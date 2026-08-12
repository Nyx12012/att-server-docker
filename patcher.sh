#!/usr/bin/env bash
# Patch the mounted game folder the way TavernLauncher-Server's Patch + Mods
# buttons do on Windows: core Root.Township.dll patch, Plugins/TavernLib.dll,
# MelonLoader, and the voice mod — all extracted from ONE pinned TavernLauncher
# release zip (Modding Tavern's own released files; the game itself stays yours).
# Since v1.8.3 the kit also overlays Plugins/TavernLib.dll with a pinned
# TavernLib release asset, because the launcher-bundled DLL has shipped stale or
# broken more than once (see TAVERNLIB_VERSION below). The core patch itself gets
# the same treatment for the same reason (see BASEPATCH_VERSION).
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
WANT="${TAVERN_VERSION:-v1.8.3}"     # pinned; "latest" tracks upstream releases

# TavernLib moves independently of the launcher. v1.8.3 bundles the v1.5.0
# build, whose KCP auth rejects brand-new joiners; the fixed v1.5.1 exists ONLY
# as a release asset (its git tag points at the same commit as v1.5.0 — only the
# binary differs). So after the launcher patch we install the pinned TavernLib
# release asset over the bundled DLL. TAVERNLIB_VERSION=bundled keeps the
# launcher's own copy; "latest" tracks TavernLib releases.
TLWANT="${TAVERNLIB_VERSION:-v1.5.1}"
TLSUM="${TAVERNLIB_SHA256:-}"
[ "$TLWANT" = "v1.5.1" ] && [ -z "$TLSUM" ] && TLSUM="3c02046c9647821ea549f35a113d4f8f48a0130252b7efc8d83dae7a98bd6074"

# The core patch moves independently too, and it is NOT versioned by the launcher
# release. On Windows the Patch button downloads themoddingtavern.dll from
# TavernDefaults' *latest* release every time; the copy inside a launcher zip is
# frozen at whatever was current the day that zip was cut. v1.8.3's zip carries
# the TavernDefaults v1.5 build, and v1.5.1 — the global-populations hotfix,
# published 2026-08-11 — exists ONLY as a release asset, with no new launcher.
# So we overlay it exactly like TavernLib. BASEPATCH_VERSION=bundled keeps the
# zip's copy; "latest" tracks TavernDefaults the way the Windows launchers do.
BPWANT="${BASEPATCH_VERSION:-v1.5.1}"
BPSUM="${BASEPATCH_SHA256:-}"
[ "$BPWANT" = "v1.5.1" ] && [ -z "$BPSUM" ] && BPSUM="06e1fc38f1b1a592d30dcce34fe26b608d5c56761e7a23b8e165c32c8063d735"

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

if [ "$TLWANT" = "latest" ]; then
  TLWANT="$(curl -sfI -o /dev/null -w '%{redirect_url}' \
    "https://github.com/ModdingTavern/TavernLib/releases/latest" | sed 's|.*/||')"
  [ -n "$TLWANT" ] || die "could not resolve the latest TavernLib release. Pin TAVERNLIB_VERSION or set it to 'bundled'."
fi

if [ "$BPWANT" = "latest" ]; then
  BPWANT="$(curl -sfI -o /dev/null -w '%{redirect_url}' \
    "https://github.com/ModdingTavern/TavernDefaults/releases/latest" | sed 's|.*/||')"
  [ -n "$BPWANT" ] || die "could not resolve the latest TavernDefaults release. Pin BASEPATCH_VERSION or set it to 'bundled'."
fi

# Both pins go in the stamp, so bumping either one re-patches on the next boot.
WANTSTAMP="$WANT"
[ "$TLWANT" != "bundled" ] && WANTSTAMP="$WANTSTAMP+tavernlib-$TLWANT"
[ "$BPWANT" != "bundled" ] && WANTSTAMP="$WANTSTAMP+base-$BPWANT"

HAVE=""
[ -f "$STAMP" ] && HAVE="$(cat "$STAMP")"
if [ "$FORCE" != "force" ] && [ "$HAVE" = "$WANTSTAMP" ] \
   && [ -f "$GAME_DIR/Plugins/TavernLib.dll" ] && [ -f "$GAME_DIR/version.dll" ]; then
  log "game folder already patched for TavernLauncher $WANTSTAMP"
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

# Overlay the pinned TavernDefaults base patch over the launcher zip's frozen
# copy (see header). This is the same file the Windows Patch button installs, so
# pinning it here is what keeps a headless box on the same build as the players.
if [ "$BPWANT" != "bundled" ]; then
  BPURL="https://github.com/ModdingTavern/TavernDefaults/releases/download/$BPWANT/themoddingtavern.dll"
  log "overlaying base patch (TavernDefaults $BPWANT)…"
  curl -sfL --retry 3 -o "$TMP/themoddingtavern.release.dll" "$BPURL" \
    || die "download failed: $BPURL — set BASEPATCH_VERSION=bundled to keep the launcher zip's copy."
  if [ -n "$BPSUM" ]; then
    printf '%s  %s\n' "$BPSUM" "$TMP/themoddingtavern.release.dll" | sha256sum -c - >/dev/null \
      || die "TavernDefaults $BPWANT sha256 mismatch — the asset changed upstream. Verify it, then set BASEPATCH_SHA256 to the new hash (or blank to skip the check)."
  else
    log "NOTE: no BASEPATCH_SHA256 for $BPWANT — installing unverified"
  fi
  cp -f "$TMP/themoddingtavern.release.dll" "$MANAGED/Root.Township.dll"
fi

log "installing Plugins/TavernLib.dll"
mkdir -p "$GAME_DIR/Plugins"
cp -f "$TMP/TavernLib.dll" "$GAME_DIR/Plugins/TavernLib.dll"

# Overlay the pinned TavernLib release asset over the bundled DLL (see header).
# Fails loudly rather than silently keeping a bundled DLL with a known join bug.
if [ "$TLWANT" != "bundled" ]; then
  TLURL="https://github.com/ModdingTavern/TavernLib/releases/download/$TLWANT/TavernLib.dll"
  log "overlaying TavernLib $TLWANT release asset…"
  curl -sfL --retry 3 -o "$TMP/TavernLib.release.dll" "$TLURL" \
    || die "download failed: $TLURL — set TAVERNLIB_VERSION=bundled to keep the launcher's own TavernLib."
  if [ -n "$TLSUM" ]; then
    printf '%s  %s\n' "$TLSUM" "$TMP/TavernLib.release.dll" | sha256sum -c - >/dev/null \
      || die "TavernLib $TLWANT sha256 mismatch — the asset changed upstream. Verify it, then set TAVERNLIB_SHA256 to the new hash (or blank to skip the check)."
  else
    log "NOTE: no TAVERNLIB_SHA256 for $TLWANT — installing unverified"
  fi
  cp -f "$TMP/TavernLib.release.dll" "$GAME_DIR/Plugins/TavernLib.dll"
fi

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

printf '%s\n' "$WANTSTAMP" > "$STAMP"
log "done — game folder is on TavernLauncher $WANTSTAMP (your own mods untouched)"
