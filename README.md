# luckfox-pico-alpine

Alpine Linux for the **Luckfox Pico (RV1103, SD card boot)**, built from source and
reproducible. Every push to `main` builds a fresh `sd_update.img` in GitHub Actions;
pushing a `v*` tag also publishes it as a release.

## What the image gives you

- Alpine 3.24 (OpenRC) on the SD card, rootfs grown to fill the card on first boot
- Serial console on UART2 (115200) with root autologin
- Network + SSH over the USB-C cable: the Pico appears as a USB Ethernet device
  ("PicoAlpine") at `192.168.2.50`
- 55 MB usable RAM (camera CMA reservation reduced from 24M to 1M)
- Swap: 48 MB zram (priority 100) + the 256 MB `userdata` partition on the SD card

## Repository layout

```
sdk/            submodule: LuckfoxTECH/luckfox-pico, pinned upstream commit (untouched)
patches/        changes applied to sdk/ at build time
overlay/        files copied over the Alpine rootfs (/etc/...)
packages.txt    packages installed into the rootfs (Alpine's /etc/apk/world)
scripts/        build steps that run inside containers, plus pull-from-pico.sh
build.sh        runs the whole build (used by CI and locally)
config.env      Alpine version, board config, default password, SDK build image
```

`patches/luckfox-pico.patch` sets the camera CMA reservation to 1M, removes the
SDK's Buildroot overlays (they overwrite Alpine files and leak build-host ownership),
and enables zram in the kernel. Enabled services are listed in
`scripts/build-rootfs.sh` (`BOOT_SERVICES`, `DEFAULT_SERVICES`).

## Login

Default login is **`root` / `toor`** (serial console logs in automatically).
Change it after first boot with `passwd`. SSH is only reachable over the USB cable
from the computer the Pico is plugged into.

To build images with a different default, change `ROOT_PASSWORD` in `config.env`, or
keep it out of git by setting the repository secret `ROOT_PASSWORD_HASH` (overrides it):
```sh
openssl passwd -6 | gh secret set ROOT_PASSWORD_HASH
```

SSH host keys are not stored anywhere: sshd generates them on first boot, so they
change after every reflash. Clear the old one with `ssh-keygen -R 192.168.2.50`.

## Making changes

**Rootfs - change things on the Pico, then capture them:**
```sh
./scripts/pull-from-pico.sh                 # updates tracked files + packages.txt
./scripts/pull-from-pico.sh etc/motd        # also start tracking a new file
ssh root@192.168.2.50 'apk audit'           # lists files changed vs. packages
git diff && git commit -am "..." && git push
```

**SDK / kernel / U-Boot:** edit files under `sdk/` (the patch is already applied there
after a build), then save the result as the patch:
```sh
git -C sdk diff > patches/luckfox-pico.patch
```

**Moving to a newer SDK:**
```sh
git -C sdk checkout -- . && git -C sdk fetch --depth 1 origin <commit>
git -C sdk checkout <commit> && git -C sdk apply ../patches/luckfox-pico.patch
git add sdk patches && git commit -m "Bump Luckfox SDK"
```

## Building locally

Needs Linux with Docker and arm/v7 emulation (e.g. a Lima VM; on a fresh machine run
`docker run --privileged --rm tonistiigi/binfmt --install arm`).
```sh
git clone --recurse-submodules --shallow-submodules <this repo>
./build.sh                     # or: DOCKER="sudo docker" ./build.sh
```
The image is written to `out/sd_update.img`. Buildroot is never built: the SDK only
checks that its rootfs tarball exists, so the build supplies an empty placeholder and
packs the Alpine rootfs instead.

## Flashing

Download `sd_update.img.xz` from the
[latest release](../../releases/latest) (or a workflow run's Artifacts) and flash it
to a microSD card with balenaEtcher (it reads `.xz` directly) or:
```sh
xz -dc sd_update.img.xz | sudo dd of=/dev/rdiskN bs=4m   # macOS
```
On first boot `firstboot.start` creates the SD swap and grows the rootfs; the
"read swap header failed" message on that first boot is expected.

## Connecting

1. **Serial:** UART2_TX_M1 / UART2_RX_M1 / GND at 3.3 V, 115200 8N1
   (e.g. `picocom -b 115200 /dev/cu.usbserial-*`).
2. **USB network:** plug the Pico's USB-C into your computer. A "PicoAlpine" Ethernet
   device appears. The Pico is `192.168.2.50/24` with gateway `192.168.2.1`:
   - macOS: System Settings > General > Sharing > Internet Sharing, share Wi-Fi to
     PicoAlpine (gives the Mac `192.168.2.1`), then `ssh root@192.168.2.50`
   - Linux: `sudo ip addr add 192.168.2.1/24 dev <usb iface>` (add NAT for internet)
3. The board has no RTC; chrony sets the clock once it has internet.
