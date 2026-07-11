# Make your `game.zip` (Windows, one time)

**You only need this if you're HOSTING your own server.** If you just want to *join*
someone's server, you don't need any of this — patch your game the normal way and type
their IP.

This produces one file — **`game.zip`** — which is your own patched copy of the game.
The server kit ships no game files, so you make this yourself. Takes ~15 minutes.

**You need:** a Windows PC and *A Township Tale* (a **free** download on Steam).

---

## 1. Install the game (free)

If it's not already installed: get **A Township Tale** on Steam and let it finish
downloading. You do **not** need a VR headset for this part.

## 2. Patch it with TavernLauncher

Use the **Modding Tavern TavernLauncher** — the same tool you use to play modded ATT.

1. Open TavernLauncher.
2. Choose the **Server** option (not Client), then click **Patch** and let it finish.
   *(If you run any mods, apply them too.)*
3. When it's done, it has turned a copy of the game into a **server folder**.

> Not sure where the folder is? It's usually your Steam game folder:
> `C:\Program Files (x86)\Steam\steamapps\common\A Township Tale`
> (In Steam you can also right-click the game → **Manage → Browse local files**.)

## 3. Check you have the right folder ✅

Open that folder. It's correct **only if you can see all of these** inside it:

- `A Township Tale.exe`
- `version.dll`   ← this one means the patch worked (don't skip it)
- a folder named `A Township Tale_Data`
- a folder named `MelonLoader`
- `Plugins\TavernLib.dll`   (inside the `Plugins` folder)

If `version.dll` or `Plugins\TavernLib.dll` are missing, the patch didn't fully apply —
run TavernLauncher's **Patch** again.

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
