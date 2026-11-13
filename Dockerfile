# Builds the Telegram Desktop image. Start the container with compose.yaml, not with this file.
FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive
# The official release build from https://github.com/telegramdesktop/tdesktop/releases
# Qt is built into the Telegram binary: the release build is one executable, no Qt libraries
# to install. This build contains no Qt WebEngine, so there is no embedded Chromium and no
# Chromium sandbox inside the Telegram process itself.
COPY td-setup-linux-x64-7.4.3.tar.xz /tmp/tg.tar.xz
# The checksum GitHub publishes for the release asset. The build stops if your download does
# not match it. When you raise the version, put the new checksum here.
RUN apt-get update \
 && apt-get install -y --no-install-recommends xz-utils \
 && apt-get clean && rm -rf /var/lib/apt/lists \
 && echo 'a2032e74a3c57c183cc280938b89d85d965fd8d1eacbfb5967faa7b3bee402ca  /tmp/tg.tar.xz' | sha256sum -c \
 && tar -xJf /tmp/tg.tar.xz -C /opt \
 && chown -R 65534:65534 /opt/Telegram \
 && rm /tmp/tg.tar.xz
# /opt/Telegram is the update channel: compose.yaml mounts the tg-bin volume here. Docker
# copies the files above into an empty volume at the first start, keeping the owner set
# here, so the Updater (uid 65534) can replace the binary. The Updater downloads over
# HTTPS from Telegram's servers. It checks the TLS connection, but on Linux it verifies no
# signature or checksum: this is the one place the jail trusts Telegram's update servers
# without an independent check. The volume keeps the newest version across rebuilds; to
# go back to the version pinned in this file, delete the volume.
# What the Telegram binary loads from the system, taken from ldd: the X and XCB client
# libraries, GLib, Cairo, Pango, FreeType, Fontconfig, HarfBuzz, zlib.
# The Wayland libraries: the binary loads them at runtime (dlopen, so ldd does not list them)
# and draws through Wayland. The X libraries stay because the binary links them.
# libasound2t64: sound output for voice messages.
# fonts-noto-cjk: Chinese fonts. The container cannot use the fonts of the host.
# firefox: a browser for the links you open in Telegram. This Telegram build has no built-in
# browser, so it gives every link to xdg-open. The firefox package in the Ubuntu archives
# installs a snap, and a snap cannot run in this container. So add the Mozilla repository,
# with a preference that selects its package instead of the snap stub. curl is used once for
# the key and removed again in the same layer.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && install -d /etc/apt/keyrings \
 && curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/mozilla.asc \
 && echo 'deb [signed-by=/etc/apt/keyrings/mozilla.asc] https://packages.mozilla.org/apt mozilla main' > /etc/apt/sources.list.d/mozilla.list \
 && printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla \
 && apt-get update \
 && apt-get install -y --no-install-recommends firefox \
      libwayland-client0 libwayland-cursor0 libwayland-egl1 libwayland-server0 libegl1 libgbm1 libxkbcommon0 \
      libasound2t64 libx11-6 libxext6 libxrender1 libxcb1 libxcb-render0 libxcb-shm0 \
      libglib2.0-0t64 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 \
      libfreetype6 libfontconfig1 libharfbuzz0b zlib1g \
      fonts-noto-cjk fontconfig ca-certificates xdg-utils \
 && apt-get purge -y --auto-remove curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists \
 && mkdir -p /home/telegram \
 && chown 65534:65534 /home/telegram
# This file does not set a user. compose.yaml sets the user to uid 65534.
ENV HOME=/home/telegram \
    QT_ACCESSIBILITY=0
# No flags are needed here. Telegram is not Electron: there is no Chromium sandbox to
# switch off, because this build has no Qt WebEngine. It draws through Wayland shared memory
# buffers, which needs no GPU.
ENTRYPOINT ["/opt/Telegram/Telegram"]
