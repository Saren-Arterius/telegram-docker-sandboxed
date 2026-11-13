# Telegram Desktop in a Docker jail

Telegram now runs code from strangers' messages (mini apps, widgets); a bot message popped
RCE on Android in November 2026. Here, anything Telegram runs gets uid 65534, no
capabilities, seccomp, a read-only root, no LAN or host access, and only the folders below.

## Setup

```
curl -fLO https://github.com/telegramdesktop/tdesktop/releases/download/v7.4.3/td-setup-linux-x64-7.4.3.tar.xz
echo "XDG_DOWNLOAD_DIR=\"$(xdg-user-dir DOWNLOAD)\"" > .env
echo "COMPOSE_FILE=compose.yaml:compose.wayland.yaml" >> .env   # or compose.x11.yaml
mkdir -p "$(xdg-user-dir DOWNLOAD)/Telegram Desktop"             # else Docker creates it as root
sed "s|@DIR@|$PWD|g" telegram-docker.desktop > ~/.local/share/applications/org.telegram.desktop._3e485da34fc040f9218e3891ecde1e6c.desktop
docker compose up -d
```

Use Wayland if you can: on X11 any client can keylog and type into other X11 windows.

## What Telegram can reach

- `~/Downloads`: your downloads folder, read-only; `Telegram Desktop/` inside is writable.
  It's also mounted at its host path, so drag and drop works from there only.
- `share/`: read-write exchange folder.
- The internet. Private ranges, multicast, the host and other containers are rejected by
  the `TG_JAIL` iptables chain, which `x-grant` installs on every start.
- Links open in a Firefox inside the same jail.

## Notes

- **Dock grouping**: the launcher's file name is Telegram's Wayland app ID; X11 matches
  `StartupWMClass=TelegramDesktop` and needs `uts: host`, because GNOME ignores windows
  from another hostname. If the app ID ever changes:
  `docker compose run --rm -e WAYLAND_DEBUG=1 telegram 2>&1 | grep -o 'set_app_id("[^"]*")'`
- **Launcher** runs `docker compose` in `Path=`, because `COMPOSE_FILE` is relative.
- **Updates**: Telegram updates itself into the `tg-bin` volume. Its updater checks no
  signature, only TLS. To pin a version instead, change the tarball and checksum in
  `Dockerfile`, then
  `docker compose down && docker volume rm telegram-docker-sandboxed_tg-bin && docker compose up -d --build`.
- `libEGL`/`MESA` warnings are expected: there is no GPU, so Qt draws in software.

## Check

```
docker exec telegram-docker-sandboxed-telegram-1 grep -E 'CapEff|NoNewPrivs|Seccomp:' /proc/1/status
# CapEff 0000000000000000, NoNewPrivs 1, Seccomp 2
```

## Remove

```
docker compose down -v
sudo iptables -D INPUT -s 172.27.0.0/24 -j TG_JAIL
sudo iptables -D DOCKER-USER -s 172.27.0.0/24 -j TG_JAIL
sudo iptables -F TG_JAIL && sudo iptables -X TG_JAIL
setfacl -x u:65534 "$(xdg-user-dir DOWNLOAD)/Telegram Desktop"
```
