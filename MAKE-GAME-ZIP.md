# Make your `game.zip` (Windows, one time)

**You only need this if you're HOSTING your own server.** If you just want to *join*
someone's server, you don't need any of this — patch your game the normal way and type
their IP.

This produces one file — **`game.zip`** — which is your own copy of the game.
The server kit ships no game files, so you make this yourself. Takes ~10 minutes.

**You need:** a Windows PC and *A Township Tale* (a **free** download on Steam).

> **Since v1.8.1 you do NOT patch anything for the server.** The container patches
> the game itself on every start (it applies the latest pinned TavernLauncher
> release, exactly like the launcher's Patch button). A clean, unpatched copy is
> the ideal input. An already-patched folder works too — the patcher just tops it
> up — but clean is simpler and never gets out of date.

---

## 1. Install the game (free)

If it's not already installed: get **A Township Tale** on Steam and let it finish
downloading. You do **not** need a VR headset for this part.

## 2. Find the game folder

It's usually your Steam game folder:
`C:\Program Files (x86)\Steam\steamapps\common\A Township Tale`
(In Steam you can also right-click the game → **Manage → Browse local files**.)

If you have a clean backup from before you patched your client, use that instead —
it's the perfect server source.

## 3. Check you have the right folder ✅

Open the folder. It's correct **only if you can see both of these** inside it:

- `A Township Tale.exe`
- a folder named `A Township Tale_Data`

That's all the server needs — MelonLoader, TavernLib, and the core patch are
installed by the container itself. (Extra files from a patched install, like
`version.dll` or `MelonLoader\`, are fine to leave in.)

## 4. Zip it → `game.zip`

1. **Right-click** the game folder (the one you just checked).
2. Choose **Send to → Compressed (zipped) folder**.
3. Rename the new `.zip` to exactly **`game.zip`**.

That's your file. It'll be a few GB — that's normal.

---

## 5. Get it onto your server

Pick whichever is easier (full steps are in **SETUP-GUIDE.md → Part 4**):

- **Upload it directly** with one `scp` command, or
- **Put it on your own Dropbox/Drive** and paste the link into the server — often faster
  if your home upload speed is slow. (On Dropbox, end the link with `?dl=1`.)

> Keep `game.zip` to yourself — don't post it publicly. It's your licensed copy of the
> game, not something to hand around.

**Next:** go to **SETUP-GUIDE.md** and continue from **Part 2** (rent your server).
