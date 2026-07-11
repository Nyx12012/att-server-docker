# Host your own A Township Tale server — step by step

This guide is for someone who has **never touched a server or a command line**. Follow
it top to bottom and you'll have a server your friends can join by just typing your IP
into their game launcher — no files to hand around.

**What you'll need**
- A **Windows PC** (used once, to prepare the game files).
- *A Township Tale* installed on that PC (it's a **free** download on Steam).
- A **credit/debit card** for a cheap Linux server (about **$5–7 a month**).
- About **30–45 minutes** the first time.

**How it works, in one breath:** you rent a small always-on Linux computer ("a VPS"),
put your own patched copy of the game on it, and run one command. From then on the
server is online 24/7 and friends join by typing its IP address. You are **not** sharing
the game with anyone — everyone brings their own free copy.

There are 6 parts. Do them in order.

---

## Part 1 — Make your server's game files (on your Windows PC)

The kit does **not** include the game (that would be piracy — the game is free, but its
files aren't ours to hand out). So you make your own patched copy once.

> **Full step-by-step with pictures-worth-of-detail is in [MAKE-GAME-ZIP.md](MAKE-GAME-ZIP.md).**
> The short version:

1. Install **A Township Tale** from Steam if you haven't (it's free).
2. Open the **Modding Tavern TavernLauncher** (the same tool used to play modded ATT),
   choose **Server**, and click **Patch**. (Apply your mods too, if any.)
3. Find the patched folder (usually your Steam `…\common\A Township Tale` folder) and
   **check it contains all of these** — this is how you know it worked:
   `A Township Tale.exe`, **`version.dll`**, `A Township Tale_Data\`, `MelonLoader\`, and
   **`Plugins\TavernLib.dll`**. If `version.dll` or `TavernLib.dll` are missing, run **Patch** again.
4. **Zip that folder.** Right-click it → **Send to → Compressed (zipped) folder**, and
   rename the result to exactly **`game.zip`**. (A few GB is normal.)

> Keep `game.zip` private (don't post it publicly). It's your licensed copy.

---

## Part 2 — Rent a Linux server (a "VPS")

1. Pick a provider. Any of these are fine and cheap: **Contabo**, **Hetzner**,
   **DigitalOcean**, **Vultr**. (This project runs on Contabo.)
2. Create a new server ("VPS" / "Cloud Server" / "Droplet") with:
   - **Operating system: Ubuntu 22.04** (important — pick this exact one).
   - **At least 4 GB RAM** (8 GB is smoother) and **30 GB+ disk**.
   - A **root password** (write it down) — or an SSH key if the provider pushes one; a
     password is fine and simpler.
3. After a minute or two the provider shows you the server's **IP address** (four numbers
   like `144.126.133.142`). **Write this down** — it's both how you manage the server and
   what your friends will type to join.

---

## Part 3 — Connect to your server from Windows

You'll type commands on the server through a black text window. Windows has this built in.

1. Open **Windows Terminal** or **PowerShell** (search for it in the Start menu).
2. Type this, replacing the IP with **your** server's IP, and press Enter:
   ```
   ssh root@144.126.133.142
   ```
3. The first time it asks *"Are you sure you want to continue connecting?"* — type **yes**
   and Enter.
4. It asks for a password — paste the **root password** from Part 2 (right-click pastes in
   the terminal; the password stays invisible as you type — that's normal) and press Enter.

You're now "on" the server. Everything you type here runs on it. (If `ssh` doesn't work,
install the free **PuTTY** program instead and connect to the same IP as `root`.)

---

## Part 4 — Put the installer and your game files on the server

1. **Run the installer once to set things up.** Paste this into the server window and press
   Enter:
   ```
   curl -fsSL https://raw.githubusercontent.com/Nyx12012/att-server-docker/main/install.sh | bash
   ```
   It installs everything it needs and then **stops** with a message that it needs your
   game files. That's expected — do the next step.

2. **Upload your `game.zip`.** Two ways — pick one:

   **A) Straight upload (simplest).** Open a **second** Windows Terminal window (leave the
   first one connected). In the new window, run this, changing the path to where your
   `game.zip` is and the IP to your server:
   ```
   scp "C:\Users\You\Desktop\game.zip" root@144.126.133.142:~/att-server-docker/game.zip
   ```
   Enter the same root password. This copies the file up (a few GB — it can take a while
   depending on your internet upload speed).

   **B) Via a private link (faster if your upload is slow).** Put `game.zip` on your **own**
   Dropbox/Google Drive, get a share link, and make it a *direct download* (on Dropbox,
   change the link's ending from `?dl=0` to **`?dl=1`**). Then on the server, open `.env`
   and paste the link after `GAME_URL=`:
   ```
   nano ~/att-server-docker/.env
   ```
   Arrow down to the `GAME_URL=` line, paste your link right after the `=`, then press
   **Ctrl+O**, **Enter** to save and **Ctrl+X** to exit.

---

## Part 5 — Name your server and start it

1. **Set the name friends will see.** Paste this, changing the name to whatever you want:
   ```
   sed -i 's/^SERVER_NAME=.*/SERVER_NAME=Velaris Township/' ~/att-server-docker/.env
   ```
   (Letters, numbers and spaces are fine. Skip this step to keep the default name.)

2. **Run the installer again** to build and launch everything:
   ```
   cd ~/att-server-docker && ./install.sh
   ```
   The first build downloads Wine and takes a few minutes. When it finishes it prints your
   **server name** and the **join address** to give your friends. It also opens the firewall
   for you automatically.

3. **Watch it come up:**
   ```
   docker compose logs -f
   ```
   Good signs scroll by: `Melon Assembly loaded: 'Plugins/TavernLib.dll'` and the world
   loading. Red `webapi.townshiptale.com` lines are **normal** (old dead Alta servers).
   Press **Ctrl+C** to stop watching (this does **not** stop the server).

Your server is now live and will stay online, restart itself if it crashes, and come back
after a reboot.

---

## Part 6 — Open ports in your provider's firewall (only if needed)

`install.sh` already set the firewall **on the server**. But **some providers** (often
DigitalOcean, AWS, Oracle) also have a **separate firewall in their website's control
panel**. If your friends can't connect, log into your provider's website, find
**Firewall / Networking**, and allow **inbound**:

- **1757** — both **TCP and UDP**
- **1761** — **TCP**

Leave everything else as-is. (Contabo and Hetzner usually need nothing here.)

---

## How your friends join (send them this)

Your friends do **not** need anything from you except your **IP address**. Each friend:

1. Owns *A Township Tale* (free) and has patched it with **TavernLauncher – Client** (the
   normal way people play modded ATT).
2. Opens the launcher, **types your server's IP** (e.g. `144.126.133.142`), and clicks
   **Join**.

That's it — they load straight into your world. No files, no passwords.

> Voice chat won't work (it relied on Alta's old servers) — everyone uses Discord instead.

---

## Everyday commands

Run these after connecting (Part 3) and `cd ~/att-server-docker`:

| I want to… | Command |
|---|---|
| See the live log | `docker compose logs -f` (Ctrl+C to stop watching) |
| Stop the server | `docker compose down` |
| Start it again | `docker compose up -d` |
| Restart it | `docker compose restart` |
| Change the server name | edit `.env` (Part 5, step 1), then `docker compose up -d` |
| Update the kit | `cd ~/att-server-docker && git pull && ./install.sh` |

---

## If something's wrong

- **Friends can't connect at all** → check Part 6 (provider firewall), and make sure the
  server is running: `docker compose ps` should show `att-server` **Up**.
- **They get in but the ground/terrain is broken** → port **1761/TCP** isn't open. On the
  server: `ufw allow 1761/tcp && ufw reload`, and check Part 6.
- **The launcher just spins on "authenticating" when a friend joins** → the listing isn't
  live. On the server: `docker logs att-register` (should be quiet = working). Make sure the
  server can reach the internet. Give it a minute after starting.
- **"No game files yet" when you run the installer** → your `game.zip` isn't in the right
  place. It must be at `~/att-server-docker/game.zip`. Re-do Part 4.
- **Still stuck?** Copy the last ~20 lines of `docker compose logs -f` and send them to
  whoever shared this kit with you.
