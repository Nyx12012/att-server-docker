# TavernVoice — client voice mod

`TavernVoice.dll` is the **one file** a player drops into their game's `Mods\` folder to
get self-hosted **proximity voice** on any server running this kit's voice relay.

- **Install (non-technical):** see **[../CLIENT-VOICE-INSTALL.md](../CLIENT-VOICE-INSTALL.md)**.
- **What it does:** captures your mic → Opus (Concentus, embedded) → UDP to the server's
  relay; plays every nearby speaker through a positional in-world audio source. Auto-connects
  to the box you joined on the relay port (default 1765). If no relay answers, it's silent —
  never crashes.
- **One DLL, every server.** No per-server config. Nothing here contains game files.

Source + build script live in the mod's own project folder (not shipped here).
