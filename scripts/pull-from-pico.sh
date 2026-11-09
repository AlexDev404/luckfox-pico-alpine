#!/usr/bin/env bash
# Copies the current versions of every file tracked in overlay/ (plus the
# installed package list) from a running Pico back into this repo.
# Add new files by passing their paths:  ./scripts/pull-from-pico.sh etc/motd
set -euo pipefail
cd "$(dirname "$0")/.."

HOST=${PICO:-root@192.168.2.50}
FILES=$( (cd overlay && find . -type f | sed 's|^\./||'; printf '%s\n' "$@") | sort -u | tr '\n' ' ')

ssh "$HOST" "cd / && tar czf - $FILES etc/apk/world" | tar xzf - -C overlay
mv overlay/etc/apk/world packages.txt

git status --short
echo "Review with 'git diff', then commit and push to rebuild."
