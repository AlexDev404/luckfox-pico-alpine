#!/bin/sh
# Builds the Alpine root filesystem tarball.
# Runs INSIDE an arm32v7/alpine container (see ../build.sh):
#   /repo  this repository (read-only)
#   /out   output directory; alpine.tar.gz is written here
# Env: ROOT_PASSWORD       plain default password (from config.env)
#      ROOT_PASSWORD_HASH  crypt hash; overrides ROOT_PASSWORD when set
set -eu

BOOT_SERVICES="devfs procfs sysfs swap usb-gadget"
DEFAULT_SERVICES="networking sshd chronyd local"
ST=/stage

echo "--- installing packages"
apk update
# shellcheck disable=SC2046
apk add $(grep -v '^[[:space:]]*#' /repo/packages.txt)

echo "--- staging filesystem"
rm -rf "$ST" && mkdir "$ST"
for d in bin etc lib root sbin usr var; do cp -a "/$d" "$ST/"; done
rm -rf "$ST"/var/cache/apk/*
for d in dev proc run sys tmp home media mnt opt srv; do mkdir -p "$ST/$d"; done
chmod 1777 "$ST/tmp"
mkdir -p "$ST/var/empty" "$ST/var/spool/cron/crontabs"

echo "--- applying overlay"
cp -a /repo/overlay/. "$ST/"
# files checked out by git belong to the CI/host user; make them root's
(cd /repo/overlay && find . -mindepth 1) | while read -r p; do chown -h 0:0 "$ST/$p"; done
chmod 600 "$ST/etc/crontabs/root"

echo "--- timezone"
cp "/usr/share/zoneinfo/$(cat "$ST/etc/timezone")" "$ST/etc/localtime"

echo "--- services"
for s in $BOOT_SERVICES $DEFAULT_SERVICES; do
  [ -e "$ST/etc/init.d/$s" ] || { echo "missing init script: $s" >&2; exit 1; }
done
for s in $BOOT_SERVICES; do ln -sf "/etc/init.d/$s" "$ST/etc/runlevels/boot/$s"; done
for s in $DEFAULT_SERVICES; do ln -sf "/etc/init.d/$s" "$ST/etc/runlevels/default/$s"; done

echo "--- root password"
if [ -z "${ROOT_PASSWORD_HASH:-}" ] && [ -n "${ROOT_PASSWORD:-}" ]; then
  ROOT_PASSWORD_HASH=$(cryptpw -m sha512 "$ROOT_PASSWORD")
fi
if [ -n "${ROOT_PASSWORD_HASH:-}" ]; then
  awk -F: -v OFS=: -v h="$ROOT_PASSWORD_HASH" '$1 == "root" { $2 = h } 1' \
    "$ST/etc/shadow" > /tmp/shadow
  cat /tmp/shadow > "$ST/etc/shadow" && rm -f /tmp/shadow
else
  echo "WARNING: no root password configured - root login is locked." >&2
  echo "         Serial autologin works, SSH password login will not." >&2
fi
chown root:shadow "$ST/etc/shadow"
chmod 640 "$ST/etc/shadow"
# SSH host keys are intentionally not included: sshd generates them on first boot.

echo "--- packing"
tar czf /out/alpine.tar.gz -C "$ST" .
ls -lh /out/alpine.tar.gz
