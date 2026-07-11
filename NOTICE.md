# NOTICE — game files are NOT included

This repository contains **only** deployment tooling (Docker, Wine setup, scripts).
It does **not** contain, and must never contain, *A Township Tale* game binaries or
the Modding Tavern patch. Those are Alta / Modding Tavern property.

To use this, you supply your own patched game folder — the one produced by running
the Modding Tavern **TavernLauncher** (Patch + Mods) on a copy of the game you own.
Point `ATT_GAME_DIR` at it, or host it yourself and set `GAME_URL`.

Do not commit `.env` (it holds tokens) or the `game/` folder. `.gitignore` blocks both.
