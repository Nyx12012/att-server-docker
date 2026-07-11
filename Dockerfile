# A Township Tale — headless server under Wine (Linux/VPS)
# Pass 2 build. Image carries Wine + Xvfb ONLY. Your patched game folder is
# mounted in at runtime (see docker-compose.yml / README.md) — no game binaries
# are baked into this image.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    WINEPREFIX=/wine \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    # Force MelonLoader's version.dll proxy (native) over Wine's builtin — this
    # is what lets MelonLoader inject under Wine. Without it, no mods load.
    WINEDLLOVERRIDES="version=n,b" \
    DISPLAY=:0 \
    XDG_RUNTIME_DIR=/tmp/xdg-runtime

# --- Wine repo + i386 arch ---------------------------------------------------
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wget gnupg2 ca-certificates cabextract unzip p7zip-full \
      xvfb xdg-user-dirs dbus-x11 \
 && mkdir -p /etc/apt/keyrings \
 && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
 && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
 && apt-get update \
 && apt-get install -y --install-recommends winehq-stable \
 && apt-get install -y --no-install-recommends winetricks \
 && rm -rf /var/lib/apt/lists/*

# Silence ALSA (no audio device in a container) so Unity audio init doesn't spam/fail.
RUN printf 'pcm.!default { type null }\nctl.!default { type null }\n' > /etc/asound.conf

# Initialise the Wine prefix at build so first boot is fast. The prefix is a
# VOLUME at runtime (world saves live inside it), so this just seeds it.
RUN mkdir -p "$WINEPREFIX" "$XDG_RUNTIME_DIR" \
 && wineboot --init \
 && wineserver -w

# Optional: some Unity Windows builds want VC runtimes under Wine. Left off by
# default to match known-good prior art; uncomment if the game faults on boot.
# RUN winetricks -q vcrun2019

WORKDIR /game
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Informational only: docker-compose runs this with network_mode: host, so the
# container binds these directly on the host and EXPOSE/publishing is not used.
# Official Tavern port set: 1757 game (KCP/UDP + TCP), 1761 "forest"/native web
# (/cache + Alta console REST), 1762 auth, 1763 community API (themoddingtavern.com).
EXPOSE 1757/udp 1757/tcp 1761/tcp

ENTRYPOINT ["/entrypoint.sh"]
