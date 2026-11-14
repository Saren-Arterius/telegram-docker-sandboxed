# Telegram Desktop in a rootless Podman jail

## What this is

This project runs Telegram Desktop in a locked container.

In November 2026, Telegram had a security bug: a message could run bad code on the device.
Telegram repaired this bug. But a new bug of this type can occur in the future.
If it occurs, the container stops the bad code from getting to your files, your network, and your account.

The container gives Telegram these limits:

- Telegram cannot get root access.
- Telegram cannot see your home folder. It can see only the folders in "What Telegram can see".
- Telegram cannot connect to your home network, your router, or your computer.
- Telegram can connect to the internet.

You do not need root access to run the container.

## Before you start

You must have these items:

1. Linux with a Wayland or X11 desktop.
2. The `podman` and `passt` packages.
3. A subuid range for your user.

To find your subuid range, type this command:

```
grep $USER /etc/subuid
```

If the command shows no result, type this command to add a range:

```
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
```

## Install

Do these steps in the project folder.

1. Download Telegram into the `image` folder:

   ```
   curl -fL --output-dir image -O https://github.com/telegramdesktop/tdesktop/releases/download/v7.4.3/td-setup-linux-x64-7.4.3.tar.xz
   ```

2. Write the name of your downloads folder into the `.env` file:

   ```
   echo "XDG_DOWNLOAD_DIR=\"$(xdg-user-dir DOWNLOAD)\"" > .env
   ```

3. Select your desktop type. For Wayland, type this command:

   ```
   echo "COMPOSE_FILE=compose.yaml:compose.wayland.yaml" >> .env
   ```

   For X11, use `compose.x11.yaml` in place of `compose.wayland.yaml`.

   WARNING: X11 is less safe. On X11, all programs can read your keys and type into other windows.
   Use Wayland if possible.

4. Make the two shared folders:

   ```
   mkdir -p share "$(xdg-user-dir DOWNLOAD)/Telegram Desktop"
   ```

5. Add Telegram to your app menu:

   ```
   sed "s|@DIR@|$PWD|g" telegram.desktop > ~/.local/share/applications/org.telegram.desktop._3e485da34fc040f9218e3891ecde1e6c.desktop
   ```

6. Start Telegram:

   ```
   podman compose up -d
   ```

## Use the NVIDIA GPU (optional)

Without a GPU, Telegram draws the screen with the CPU. This is satisfactory for most persons.

To use an NVIDIA GPU, do these steps:

1. Install `nvidia-container-toolkit` with CDI.
2. In the `.env` file, add `:compose.nvidia.yaml` to the end of the `COMPOSE_FILE` line.
3. Start Telegram again.

WARNING: The GPU driver gives Telegram one more path to attack your computer.
Do not use the GPU if you do not need it.

AMD and Intel GPUs do not operate with this project.

## Start and stop Telegram

To start Telegram, click "Telegram (Podman)" in your app menu.

To stop Telegram, right-click the icon and click "Stop Telegram". You can also type this command:

```
podman compose stop
```

## What Telegram can see

Telegram can see only these items:

| Item | Telegram can read | Telegram can change |
|---|---|---|
| Your downloads folder | Yes | No |
| The `Telegram Desktop` folder in your downloads folder | Yes | Yes |
| The `share` folder in this project | Yes | Yes |
| The internet | Yes | Yes |

Telegram cannot connect to:

- Your home network and your router.
- Your computer.
- Private network addresses, for example `192.168.x.x` and `10.x.x.x`.

Links in Telegram open in a Firefox in the same container.

To drag a file into Telegram, put the file in your downloads folder first.

## Make sure that the container is safe

Type this command when Telegram operates:

```
grep -E '^Uid|CapEff|NoNewPrivs|Seccomp:' /proc/$(pgrep -f /opt/Telegram/Telegram | head -1)/status
```

The result must show these values:

- `Uid` is `165533` (with the range in "Before you start"). Telegram does not use your user or root.
- `CapEff` is `0000000000000000`. Telegram has no special permissions.
- `NoNewPrivs` is `1`. Telegram cannot get more permissions.
- `Seccomp` is `2`. The system filter is on.

## Problems and solutions

**You cannot change a file that Telegram saved.**
Telegram saves files as a different user. To make the file yours, type:

```
podman unshare chown -R 0:0 <path>
```

**You changed `jail.nft` or the `jail` part of `compose.yaml`, and the change does not apply.**
Stop all containers and start them again:

```
podman compose down && podman compose up -d
```

**`podman exec` does not operate on these containers.**
This is a known Podman problem. To examine Telegram, use the "Make sure that the container is safe" command.

**The Telegram icon in your dock does not join the Telegram window.**
The file name of the app menu entry must be the same as the Telegram app ID.
To find the app ID, type:

```
podman compose run --rm -e WAYLAND_DEBUG=1 telegram 2>&1 | grep -o 'set_app_id("[^"]*")'
```

On X11, the window must also have the same hostname as your computer. `compose.x11.yaml` does this.

**You see `libEGL` or `MESA` warnings.**
These warnings are normal without the GPU file. You can ignore them.

## Telegram updates

Telegram updates itself. The updater checks the download only with TLS. It does not check a signature.

To use one fixed version, do these steps:

1. In `image/Containerfile`, change the file name and the checksum.
2. Type this command:

   ```
   podman compose down && podman volume rm telegram-podman-sandboxed_tg-bin && podman compose up -d --build
   ```

## Technical notes

These notes are for persons who change the project.

- The `jail` container sets the folder permissions. Then it loads the network rules from `jail.nft`.
  Telegram uses the network of `jail`. Telegram waits for the rules. If the rules do not load, Telegram stops.
- Healthchecks do not operate, because `podman exec` does not operate. A file in the `jail-state` volume
  tells Telegram that the rules are loaded.
- The project does not use `userns_mode: keep-id`. It stops the NVIDIA GPU from operating.
- The app menu entry runs `podman compose` in the project folder, because `COMPOSE_FILE` uses short paths.
- `MOZ_ASSUME_USER_NS=0` stops Firefox from crashing in the container.

## Remove

Type these commands in the project folder:

```
podman compose down -v
setfacl -x u:165533 share "$(xdg-user-dir DOWNLOAD)/Telegram Desktop"
```

WARNING: `podman compose down -v` deletes your Telegram login and settings.
