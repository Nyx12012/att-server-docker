# Voice chat — friend install (one file, ~2 minutes)

Your server now has **proximity voice**: you hear people who are near you in the game,
and they get quieter as they walk away. It replaces the old (dead) in-game voice.

You install it **once** by dropping a single file into your game. No accounts, no
settings, nothing to run. It works on every server that has voice turned on.

---

## Before you start

You need the game already patched the normal way — i.e. you launch *A Township Tale*
through **TavernLauncher – Client** and can join the server. That launcher also installs
the mod loader (MelonLoader) this voice mod needs, so **if you can already play on the
server, you're ready.**

You also need a **microphone** (any headset/VR mic). That's it.

---

## Install (the easy way)

**1. Get the file:** `TavernVoice.dll`
(from your server owner — Discord/link — or, once published, the one-line command below.)

**2. Find your game's `Mods` folder.** It sits next to `A Township Tale.exe`. The usual path is:

```
C:\Program Files (x86)\Steam\steamapps\common\A Township Tale\Mods
```

…but if you installed elsewhere, just find the folder that contains **A Township Tale.exe**
and open the **`Mods`** folder inside it. (If there's no `Mods` folder, make one — spelled
exactly `Mods`.)

**3. Drop `TavernVoice.dll` into that `Mods` folder.** Done.

**4. Launch the game and join the server** like you normally do. Voice just works.

---

## One-line install (optional, for the comfortable-with-PowerShell crowd)

Open PowerShell, paste this, and give it the folder that has `A Township Tale.exe`
when it asks:

```powershell
$g = Read-Host "Paste the folder that contains 'A Township Tale.exe'"
New-Item -ItemType Directory -Force "$g\Mods" | Out-Null
Invoke-WebRequest "https://raw.githubusercontent.com/Nyx12012/att-server-docker/main/client/TavernVoice.dll" -OutFile "$g\Mods\TavernVoice.dll"
Write-Host "Installed. Launch the game and join." -ForegroundColor Green
```

*(The download URL works once the owner has published the repo. Until then, use the
drag-and-drop steps above with the file the owner sent you.)*

---

## How to tell it's working

- **In game:** when a friend near you talks, you hear them from their direction; walk
  away and they fade out.
- **Proof in the log (optional):** open
  `...\A Township Tale\MelonLoader\Latest.log` and look for:
  ```
  TavernVoice 1.0 loaded — proximity voice ready
  TavernVoice: connected to <server-ip>:1765 (mic live).
  ```
  `(mic live)` = your mic was found. `(no mic — listen only)` = no mic detected (you'll
  still hear others).

---

## Muting

- **Mute yourself:** use the game's normal **mic-mute button** on the wrist menu — it now
  drives this voice system. (You can also set a keyboard key: see config below.)
- Muting is instant; your icon reflects it.

---

## Optional settings

The first time you run it, the mod writes **`Mods\TavernVoice.txt`** with friendly
defaults. You almost never need to touch it. Handy ones:

| Line | What it does |
|---|---|
| `range=25` | How far away you can still hear someone (metres). |
| `mic_device=` | Part of your mic's name if the wrong device is picked (e.g. `Quest`). |
| `mute_key=` | A keyboard mute toggle, e.g. `mute_key=V`. Blank = wrist button only. |
| `vad=0.006` | Mic sensitivity. Lower = picks up quieter speech; higher = only loud. |

Edit, save, relaunch.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| No voice at all | Make sure the file is in **`Mods`** (not the game root) and named exactly `TavernVoice.dll`. Check the log lines above. |
| I hear others but they can't hear me | Your mic wasn't found (`no mic — listen only` in the log). Set `mic_device=` to part of your mic's name, or pick a Windows default mic. |
| Robotic / cutting out | Network jitter — usually settles. If constant, tell the owner (relay may be overloaded or the range is huge). |
| Everyone is silent on one server | That server may not be running the voice relay. Nothing to fix on your end. |

Nothing here can crash your game — if voice can't connect, it simply stays silent.
