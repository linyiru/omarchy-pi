# Omarchy Pi

[![Built for Omarchy](https://raw.githubusercontent.com/tcballard/omarchy-badges/85f859029e236e784e7b05ada6dbe73506d07a91/badges/v1/built-for-omarchy.svg)](https://github.com/tcballard/omarchy-badges)

Builds an Omarchy disk image for the Raspberry Pi from Arch Linux ARM's rpi-aarch64 root, using the Raspberry Pi platform support on the [`raspberry-pi-platform`](https://github.com/linyiru/omarchy/pull/1) branch of Omarchy.

Status: a prototype. The image builds under emulation on an x86_64 host and boots on a Raspberry Pi 5 (16 GB) through first-boot setup to the Omarchy desktop, with all 16 GB and the Pi's V3D GPU.

<img src="docs/pi5-desktop.png" width="1280" alt="Omarchy on a Raspberry Pi 5: fastfetch in a terminal over the Omarchy desktop">

## Build

On Arch Linux, with `sudo`, `qemu-user-static` and `qemu-user-static-binfmt` (x86_64 hosts only), `systemd-nspawn`, `btrfs-progs`, `dosfstools`, `rsync`, `libarchive` and `base-devel`:

```bash
bin/build-image ~/Projects/omarchy ~/Projects/omarchy-pkgs omarchy-pi.img
```

The first argument is an Omarchy checkout with Raspberry Pi support, the second an [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) checkout for the `omarchy-dev` and `omarchy-settings-dev` PKGBUILDs. Downloads go to `~/.cache/omarchy-pi` (`OMARCHY_PI_CACHE`). Write the result to an SD card or USB drive with `dd` or Raspberry Pi Imager's custom image option.

## Run it on a Raspberry Pi 5

Tested on a Raspberry Pi 5 (16 GB) from a microSD card, with HDMI and wired Ethernet.

1. Write the image to the card. Check the device name with `lsblk` first; this overwrites it:

   ```bash
   sudo dd if=omarchy-pi.img of=/dev/sdX bs=4M conv=fsync status=progress
   ```

   Or with Raspberry Pi Imager, which can set the account, hostname, timezone, Wi-Fi and SSH on the card: pack the image with `bin/release-image omarchy-pi.img release/` and open the manifest it writes (`rpi-imager --repo release/omarchy-pi.rpi-imager-manifest`; on Linux Imager needs root to write, so run it with `sudo`). Choose Raspberry Pi 5, then Omarchy Pi (64-bit) and the card, fill in the customisation, and write.

2. Boot the Pi from the card with a screen and a keyboard attached. The first boot sets up the hardware, rebuilds the initramfs and asks for the owner (keyboard layout, user name, password, hostname, timezone) on tty1, then logs that user in to the Omarchy desktop. The desktop renders on the Pi's V3D GPU.

### How long it takes

The Pi needs about 47 seconds of its own time, firmware not counted, to go from a freshly written card to the Omarchy desktop. Measured on a Raspberry Pi 5 (16 GB) from a microSD card with wired Ethernet on 2026-10-03, from the journal of that boot, in seconds since the kernel started:

| step | from | to | took |
|---|---|---|---|
| kernel, initramfs and systemd up to first-boot setup | 0.0 | 6.5 | 6.5 s |
| first-boot hardware setup (pacman keyring 12.6 s, initramfs rebuild 4.0 s) | 6.5 | 26.6 | 20.1 s |
| owner setup on tty1 | 26.6 | 241.5 | waiting for input |
| owner setup finishing (user, theme, Node.js) | 241.5 | 257.2 | 15.7 s |
| graphical session up to Hyprland running | 257.2 | 262.3 | 5.1 s |

That comes to 47.4 s outside of owner setup. The firmware stage before the kernel isn't in the journal and isn't counted. This is the baseline for later work; the pacman keyring is the largest single step.

A second fresh card the same day, booting with the quiet console, took 38 seconds: 22 s from the kernel to the owner setup screen and 16 s finishing setup after the owner confirmed, shown here by a demo build's install finish screen (the released image goes straight to the desktop). [docs/install-finish-screen.md](docs/install-finish-screen.md) covers what the number counts and how the demo build works:

<img src="docs/installed-in-0m38s.jpg" width="960" alt="Installed Omarchy in 0m 38s, on a Raspberry Pi 5">

What to know:

- SSH is installed but its port is closed; open it with `sudo ufw allow 22/tcp`, or turn SSH on in Raspberry Pi Imager's settings before writing the card.
- The root partition stays at the image's size; it is not grown to fill the card.

## What the image is

- **Disk:** an MBR with a 512 MiB FAT32 boot partition and a btrfs root holding `@`, `@home`, `@log` and `@pkg`, as an Omarchy ISO install lays them out, plus a read-only `@factory` snapshot for factory reset (`bin/disk`).
- **Boot:** the way Raspberry Pi OS boots: the Pi's firmware reads `config.txt`, picks the board's device tree and overlays, and loads Raspberry Pi's kernel (Arch Linux ARM's `linux-rpi`, as `kernel8.img`) and the initramfs, with the kernel command line from `cmdline.txt`. Arch Linux ARM's root comes with the mainline `linux-aarch64` and U-Boot instead; the build replaces both. Only the root on the command line changes, to the btrfs root by UUID and its `@` subvolume.
- **Kernel upgrades:** boot once as a trial, through the firmware's tryboot, instead of the snapshot rollback Limine gives an x86 install. Before `linux-rpi` upgrades, `omarchy-rpi-boot` copies the running kernel, initramfs, device trees and overlays to `/boot/fallback/`; after, `config.txt` boots that copy and `tryboot.txt` boots the new kernel on the next reboot only. The trial reboots on a panic, on a failed initramfs and on a hang (the hardware watchdog), and commits once it reaches the desktop; one that hasn't within 5 minutes reboots. Either way the following boot is the last good kernel, whose modules stay installed until a trial commits. An update that ends in a poweroff runs the trial on the reboot after it; a trial that failed waits for the next upgrade. Verified on a Pi 5 on 2026-10-04.
- **System:** the Pi's default package set from `omarchy-pkg-defaults raspberrypi`, set up by `omarchy-apply-system --defer-provisioning --first-install` as the ISO does, with hardware setup deferred to the Pi's first boot (`/var/lib/omarchy/image/target` says `platform=raspberrypi`).
- **Raspberry Pi Imager's settings:** the hostname, account, password, timezone, keyboard layout, Wi-Fi and SSH you set in Imager's OS customisation, which it writes to the card as `rpi-preseed.toml`, are read on the first boot by `omarchy-rpi-preseed`. Owner setup then asks only for what Imager has no field for (full name and email) and shows the rest on its confirmation screen, where any of it can be changed. Wi-Fi, its country and SSH (keys, password logins, the open port) are set up before NetworkManager and sshd start. The file holds the password hash and the Wi-Fi key, so it is removed once read. Imager's Raspberry Pi Connect and interface options are skipped. Verified on a Raspberry Pi 5 with a card Imager 2.0.11 wrote, on 2026-10-04: account, password, hostname, timezone and SSH with password logins. Wi-Fi, key-only SSH and the keyboard layout are so far tested only against the file Imager writes, on the build host (`test/omarchy-rpi-preseed-test.sh`).
- **First boot:** makes the machine's own pacman keyring, runs the deferred hardware setup, rebuilds the initramfs for the board, then asks for the owner on tty1. Owner setup unpacks the Node.js tarball the image carries, so none of it needs the network. The image ships no account: Arch Linux ARM's `alarm` user is removed and root is locked until owner setup.

## Layout

- `bin/build-image` - the whole build
- `bin/release-image` - compresses an image and writes the manifest Raspberry Pi Imager opens it from, with its OS customisation offered
- `bin/build-packages` - builds the Omarchy packages and `packages/` for aarch64 on the host
- `bin/disk` - creates, mounts and snapshots the disk image
- `stages/` - run inside the image root, in order: repositories, Omarchy, boot, finalization
- `packages/omarchy-rpi-boot` - a prototype of the boot package `omarchy-lifecycle-dispatch` expects on a Pi; unencrypted roots only
- `packages/omarchy-rpi-preseed` - applies Raspberry Pi Imager's settings at first boot
- `test/` - tests that run on the build host
- `test/hardware/` - a round on a real Pi: factory reset, Imager's settings, owner setup and checks; see [docs/hardware-test.md](docs/hardware-test.md)

## Emulation workarounds

Under qemu-user some things the build needs don't work. Each is confined to the build and to the step that needs it:

- pacman runs with `--disable-sandbox` (no Landlock).
- snapper can't create `/.snapshots` (no btrfs ioctls), so `bin/disk` creates it from the host.
- iptables can't reach nftables (no netfilter netlink), so ufw's version check is answered while it writes its rules files.
- mkinitcpio's autodetect would read the build host, so the image's initramfs is built without it, and the first boot rebuilds it on the Pi.
