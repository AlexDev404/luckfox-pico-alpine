#!/usr/bin/env bash
# Builds out/sd_update.img from this repository.
# Needs Linux with Docker and arm/v7 emulation (qemu binfmt).
#
#   ./build.sh                          # normal build
#   DOCKER="sudo docker" ./build.sh     # if docker needs sudo
#   OUT=/some/dir ./build.sh            # write the image somewhere else
#   ROOT_PASSWORD_HASH='$6$...' ./build.sh   # override the default root password
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=config.env
source ./config.env

REPO=$PWD
SDK_DIR=$REPO/sdk
OUT=${OUT:-$REPO/out}
DOCKER=${DOCKER:-docker}
PATCH=$REPO/patches/luckfox-pico.patch
mkdir -p "$OUT"

echo "==> [1/3] Alpine $ALPINE_VERSION rootfs"
$DOCKER run --rm --platform linux/arm/v7 \
  -e ROOT_PASSWORD="${ROOT_PASSWORD:-}" \
  -e ROOT_PASSWORD_HASH="${ROOT_PASSWORD_HASH:-}" \
  -v "$REPO:/repo:ro" -v "$OUT:/out" \
  "arm32v7/alpine:$ALPINE_VERSION" sh /repo/scripts/build-rootfs.sh

echo "==> [2/3] Luckfox SDK (submodule sdk/) + patches"
if [ ! -e "$SDK_DIR/.git" ]; then
  git submodule update --init --depth 1 sdk
fi
git submodule status sdk
if git -C "$SDK_DIR" apply --reverse --check "$PATCH" 2>/dev/null; then
  echo "SDK patch already applied"
elif git -C "$SDK_DIR" apply --check "$PATCH" 2>/dev/null; then
  git -C "$SDK_DIR" apply "$PATCH"
else
  echo "patches/luckfox-pico.patch does not apply to sdk/." >&2
  echo "If you edited files in sdk/, either refresh the patch:" >&2
  echo "    git -C sdk diff > patches/luckfox-pico.patch" >&2
  echo "or reset them:  git -C sdk checkout -- ." >&2
  exit 1
fi

echo "==> [3/3] U-Boot, kernel and SD image"
$DOCKER run --rm --privileged \
  -e BOARD_CONFIG="$BOARD_CONFIG" \
  -v "$SDK_DIR:/home" -v "$OUT:/out" -v "$REPO/scripts:/scripts:ro" \
  "$SDK_IMAGE" bash /scripts/build-image.sh

echo "==> done: $OUT/sd_update.img"
