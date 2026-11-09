#!/bin/bash
# Builds U-Boot, the kernel and the final SD card image with the Luckfox SDK.
# Runs INSIDE the luckfoxtech/luckfox_pico container (see ../build.sh):
#   /home  the Luckfox SDK checkout (patched)
#   /out   contains alpine.tar.gz; sd_update.img is written here
# Env: BOARD_CONFIG
set -euo pipefail
cd /home

ROOTFS_DIR=output/out/rootfs_uclibc_rv1106
BUILDROOT_TAR=output/out/sysdrv_out/rootfs_uclibc_rv1106.tar

# Same effect as `./build.sh lunch`, without the interactive menu
ln -rsf "project/cfg/BoardConfig_IPC/$BOARD_CONFIG" .BoardConfig.mk

./build.sh uboot
./build.sh kernel

# The SDK refuses to package an image unless Buildroot's rootfs tarball exists.
# The rootfs is Alpine, so an empty placeholder avoids building Buildroot (~1h).
mkdir -p "$(dirname "$BUILDROOT_TAR")"
[ -f "$BUILDROOT_TAR" ] || tar cf "$BUILDROOT_TAR" -T /dev/null

rm -rf "$ROOTFS_DIR" && mkdir -p "$ROOTFS_DIR"
tar xzpf /out/alpine.tar.gz -C "$ROOTFS_DIR"

./build.sh firmware

cp output/image/sd_update.img /out/
ls -lh /out/sd_update.img
