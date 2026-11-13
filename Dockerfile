FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive
# Official release: one static-Qt binary, no WebEngine.
COPY td-setup-linux-x64-7.4.3.tar.xz /tmp/tg.tar.xz
# Checksum from the GitHub release. Update with the version.
RUN apt-get update \
 && apt-get install -y --no-install-recommends xz-utils \
 && apt-get clean && rm -rf /var/lib/apt/lists \
 && echo 'a2032e74a3c57c183cc280938b89d85d965fd8d1eacbfb5967faa7b3bee402ca  /tmp/tg.tar.xz' | sha256sum -c \
 && tar -xJf /tmp/tg.tar.xz -C /opt \
 && chown -R 65534:65534 /opt/Telegram \
 && rm /tmp/tg.tar.xz
# Wayland libs are dlopen'd, so ldd misses them. Firefox opens links; Ubuntu's package is a
# snap stub, so it comes from Mozilla's repo.
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
ENV HOME=/home/telegram \
    QT_ACCESSIBILITY=0
ENTRYPOINT ["/opt/Telegram/Telegram"]
