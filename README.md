# Telegram Desktop in a rootless Podman jail

Telegram now runs code from strangers' messages (mini apps, widgets); a bot message popped
RCE on Android in November 2026. Here, anything Telegram runs gets uid 65534, no
capabilities, seccomp, a read-only root, no LAN or host access, and only the folders below.
Rootless: no root daemon, no sudo, and an escape lands as an unused subuid, not as you.

## Setup

Needs `podman`, `passt`, and a subuid range (`grep $USER /etc/subuid`; else
`sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER`).

```
curl -fL --output-dir image -O https://github.com/telegramdesktop/tdesktop/releases/download/v7.4.3/td-setup-linux-x64-7.4.3.tar.xz
echo "XDG_DOWNLOAD_DIR=\"$(xdg-user-dir DOWNLOAD)\"" > .env
echo "COMPOSE_FILE=compose.yaml:compose.wayland.yaml" >> .env   # or compose.x11.yaml
mkdir -p share "$(xdg-user-dir DOWNLOAD)/Telegram Desktop"
sed "s|@DIR@|$PWD|g" telegram.desktop > ~/.local/share/applications/org.telegram.desktop._3e485da34fc040f9218e3891ecde1e6c.desktop
podman compose up -d
```

Use Wayland if you can: on X11 any client can keylog and type into other X11 windows.

GPU (NVIDIA, needs nvidia-container-toolkit with CDI): append `:compose.nvidia.yaml` to
`COMPOSE_FILE`, after either display file. Without it Qt draws in software. AMD/Intel GPUs
aren't wired up yet. The GPU driver is extra kernel attack
surface, so leave it off if you don't need it.

## What Telegram can reach

- `~/Downloads`: your downloads folder, read-only; `Telegram Desktop/` inside is writable.
  It's also mounted at its host path, so drag and drop works from there only.
- `share/`: read-write exchange folder.
- The internet. `jail` loads `jail.nft` into the network namespace Telegram shares,
  rejecting private ranges, multicast and the host (pasta's 169.254.1.2). Telegram waits
  for it and exits if it never finishes.
- Links open in a Firefox inside the same jail.

## Notes

- **Files Telegram writes** belong to its subuid (165533 with the range above). Fix with
  `podman unshare chown -R 0:0 <path>`.
- **Changing `jail`** (compose or `jail.nft`): `podman compose down && podman compose up -d`.
  Podman won't recreate it while Telegram depends on it.
- **No `podman exec`** into these containers: crun can't set `oom_score_adj` for exec
  sessions of containers made through the compose API. Hence no healthcheck.
- **No `userns_mode: keep-id`**: it would drop the ACLs, but breaks the NVIDIA CDI mounts.
- **Dock grouping**: the launcher's file name is Telegram's Wayland app ID; X11 matches
  `StartupWMClass=TelegramDesktop` and needs `uts: host`, because GNOME ignores windows
  from another hostname. If the app ID ever changes:
  `podman compose run --rm -e WAYLAND_DEBUG=1 telegram 2>&1 | grep -o 'set_app_id("[^"]*")'`
- **Launcher** runs `podman compose` in `Path=`, because `COMPOSE_FILE` is relative.
- **Updates**: Telegram updates itself into the `tg-bin` volume. Its updater checks no
  signature, only TLS. To pin a version instead, change the tarball and checksum in
  `image/Containerfile`, then
  `podman compose down && podman volume rm telegram-podman-sandboxed_tg-bin && podman compose up -d --build`.
- Without the GPU file, `libEGL`/`MESA` warnings are expected: Qt draws in software.

## Check

```
grep -E '^Uid|CapEff|NoNewPrivs|Seccomp:' /proc/$(pgrep -f /opt/Telegram/Telegram | head -1)/status
# Uid 165533, CapEff 0000000000000000, NoNewPrivs 1, Seccomp 2
```

## Remove

```
podman compose down -v
setfacl -x u:165533 share "$(xdg-user-dir DOWNLOAD)/Telegram Desktop"
```
