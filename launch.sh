#!/bin/sh
# Desktop entry launcher. $1: optional tg:// link.
cd "$(dirname "$0")" || exit 1
if podman compose ps -q --status running telegram | grep -q .; then
  # Telegram listens on an abstract socket in the jail netns. A second instance there hands
  # the link to it and exits.
  [ -z "$1" ] || exec podman compose run --rm --no-deps --entrypoint /opt/Telegram/Telegram telegram -- "$1"
else
  # Recreate: after a re-login the jail's display ACL is on the old socket.
  TG_URL="$1" exec podman compose up -d --force-recreate
fi
