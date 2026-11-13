# Telegram Desktop in a Docker container

Telegram Desktop, isolated in a Docker container with strict limits, in the style of the QQ
jail in `../linuxqq-docker`. Telegram is official, open-source software, but it opens
files, sticker data, links and now "mini apps" and message widgets from strangers, and it
parses them with a C++ Qt application. The reminder that this is not theoretical came on
12 November 2026:

> 📱⚠️ TELEGRAM FIXES ANDROID RCE FLAW DEMOED BY V12: A BOT MESSAGE POPPED CODE ON THE PHONE
> […] "Any telegram message can now become RCE." In the demo, a bot replies to /start and
> the phone's Calculator app opens seconds later […] Telegram confirmed the issue in
> Telegram for Android was fixed the day before and the fix had been deployed to all users.
> • Reportedly in the new interactive message widgets and their QuickJS JavaScript engine
> • Came about a day after Telegram launched messages that run as mini apps

— @DailyDarkWeb, <https://x.com/DailyDarkWeb/status/2120923550236160235>

Telegram confirmed that one as Android-only — the desktop client was not the vulnerable
code. But the entry point (attacker-controlled code inside an ordinary bot's message, run
by a JavaScript engine) is now a Telegram product feature on every platform, and the
desktop client parses the same messages with C++. This jail is for the desktop edition of
that headline: code executed by Telegram then runs as uid 65534, with no capabilities, a
seccomp filter, no access to your files, and no access to your computer.

## Files

| File          | What it is                                                        |
| ------------- | ----------------------------------------------------------------- |
| `Dockerfile`  | Builds the image from the official release tarball.               |
| `compose.yaml`| Runs the jail: setup service, container limits, firewall, network. |
| `td-setup-linux-x64-*.tar.xz` | The official Telegram build. Not in git; see below. |
| `share/`                | File exchange with Telegram, plus the X cookie. Created at first start. |
| `telegram-docker.desktop` | The launcher: install to `~/.local/share/applications/` (a copy, or symlink it). |

## Requirements

Docker with the compose plugin, GNOME on Wayland (XWayland), and your display at `:0`.
The paths for your X cookie (`/run/user/1000`) and your downloads folder are written in
`compose.yaml`; adjust them on a different machine.

## First use

1. Download the tarball (about 86 MB) into this directory:

   ```
   curl -fLO https://github.com/telegramdesktop/tdesktop/releases/download/v7.4.3/td-setup-linux-x64-7.4.3.tar.xz
   ```

2. Start:

   ```
   docker compose up -d
   ```

   `x-grant` runs first, as root: it copies the X cookie, opens the ACLs, installs the
   firewall rules. Telegram starts only if every step succeeded. A Telegram login window
   appears on your desktop. Sign in with your phone number. Your login and history live in
   the `tg-home` volume and survive restarts; nothing is written to your home directory
   except the files Telegram saves into your downloads folder.

## Daily use

```
docker compose up -d      # start
docker compose stop       # stop
docker compose down       # stop and remove the containers (the volume stays)
```

Telegram received media go to `/home/saren/下載/Telegram Desktop` on the host, the folder
you already had; inside the container it is `~/Downloads`, Telegram's default, so nothing
needs configuring. The folder keeps you as its owner; `x-grant` gives uid 65534 access
through an ACL entry only. Other files you want to hand to Telegram: drop them in `share/`.

## How the jail is built

The official tarball is one executable with Qt built in — no Qt libraries are installed.
This build contains no Qt WebEngine: there is no embedded Chromium, so Telegram itself runs
no browser process, needs no `--no-sandbox` flag, and its only browser is the container's
Firefox (see "Links" below). The jail:

- `user: 65534` (nobody), `cap_drop: ALL`, `no-new-privileges`, Docker's default seccomp
  profile, `read_only` root filesystem, a `noexec` `/tmp`, 6 GB memory, 4096 processes.
- Its own bridge network on `172.27.0.0/24`. The QQ jail owns `172.26.0.0/24`; two bridges
  cannot reach each other, so the two jailed messengers cannot see one another either.
- Firewall chain `TG_JAIL`, installed by `x-grant`, jumped to from both `INPUT` (blocks
  your host: sshd, syncthing, dev servers, tailscale) and `DOCKER-USER` (blocks the LAN,
  other subnets, other containers). Everything private is rejected: multicast, `127.0.0.0/8`,
  `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`, `169.254.0.0/16`.
  Public internet is allowed, which Telegram needs. The DNS accept rule names `127.0.0.11`
  explicitly — an unqualified `udp/53 ACCEPT` was tested in the QQ jail and leaked DNS
  queries to the LAN router.
- The only host paths inside: the X socket (read-only, plus a cookie), `/etc/localtime`,
  `share/`, and your `Telegram Desktop` downloads folder. No `/dev/dri`: Qt draws through
  X11 and the host renders, so the jail needs no GPU.

## Links and the browser

Telegram has no built-in browser in this build, so it gives every link to `xdg-open`, and
`xdg-open` starts Firefox inside the container. The firewall and every limit apply to that
Firefox exactly as they apply to Telegram. Firefox runs without its own sandbox (Docker's
seccomp profile blocks the user namespace it needs, and the container has no capabilities):
here the container is the sandbox. It comes from `packages.mozilla.org`, the one
third-party source in the image; Ubuntu's own package is a snap, and snaps cannot run in a
container. Firefox keeps its profile in the `tg-home` volume, so logins you make there
persist. Delete the volume to erase both.

## Dock icon and stopping

Two settings in `compose.yaml` make Telegram behave like a normal desktop app:

- **`uts: host`**: the window groups under the "Telegram (Docker)" launcher. Without it,
  the container has a random hostname, and X11 windows report it as `WM_CLIENT_MACHINE`.
  GNOME Shell treats a window from another machine as remote and never matches it to a
  `.desktop` file, so the dock shows a separate gear icon named `TelegramDesktop`.
  `StartupWMClass` cannot fix this, and neither can logging out and back in. Sharing the
  host's UTS namespace makes the hostname match without hardcoding it. The container has
  no capabilities, so it can read the hostname but cannot change it. The launcher still
  needs `StartupWMClass=TelegramDesktop`, the class part of the window's
  `WM_CLASS` (`"Telegram", "TelegramDesktop"`).
- **`init: true`**: `docker compose stop` (and the launcher's "Stop Telegram" action)
  takes under a second instead of 10. Without it, Telegram runs as PID 1. The kernel
  delivers no signal to PID 1 unless the process installed a handler for it, and Telegram
  installs none for SIGTERM, so Docker waited its full 10-second timeout before SIGKILL.
  With `init: true`, tini runs as PID 1 and passes the signal on to Telegram.

To debug grouping, check both properties of the running window:

```
DISPLAY=:0 xprop WM_CLASS WM_CLIENT_MACHINE   # then click the Telegram window
```

## Check the container

```
docker exec telegram-docker-sandboxed-telegram-1 grep -E 'CapEff|NoNewPrivs|Seccomp:' /proc/1/status
# Expect: CapEff 0000000000000000, NoNewPrivs 1, Seccomp 2
```

```
docker exec telegram-docker-sandboxed-telegram-1 sh -c \
  'ip=$(getent ahostsv4 telegram.org | cut -d" " -f1); timeout 4 bash -c "echo > /dev/tcp/$ip/443" && echo INTERNET-OPEN; timeout 3 bash -c "echo > /dev/tcp/172.27.0.1/22" && echo HOST-OPEN || echo host-blocked'
# Expect: INTERNET-OPEN (Telegram's own servers) and host-blocked.
```

## Updates

Auto-update is on. `/opt/Telegram` is the `tg-bin` volume, seeded from the image at first
start, so Telegram's own Updater can replace the binary in place and the new version
survives restarts and rebuilds. The trust this asks for: the Updater downloads over HTTPS
from Telegram's servers and verifies the TLS connection only — on Linux it checks no
signature or checksum. Everything it installs still runs inside this jail, so a bad update
costs you the container's contents, not your computer. If that trade is ever unacceptable,
delete the volume and the pinned version returns.

To pin a new version instead (the checked path: you download the tarball, GitHub publishes
its checksum, the build refuses a mismatch): fetch the newest
`td-setup-linux-x64-<ver>.tar.xz` from the releases page, update the version and checksum
in `Dockerfile`, then

```
docker compose down && docker volume rm telegram-docker-sandboxed_tg-bin && docker compose up -d --build
```

The volume removal matters: an existing volume is not re-seeded, so without it the volume
would keep whatever version the Updater last wrote.

## Remove everything

```
docker compose down -v        # -v removes tg-home and tg-bin
sudo iptables -D INPUT -s 172.27.0.0/24 -j TG_JAIL
sudo iptables -D DOCKER-USER -s 172.27.0.0/24 -j TG_JAIL
sudo iptables -F TG_JAIL && sudo iptables -X TG_JAIL
```

The ACL entries on your downloads folder stay; remove them with
`setfacl -x u:65534 '/home/saren/下載/Telegram Desktop'` if you want.
