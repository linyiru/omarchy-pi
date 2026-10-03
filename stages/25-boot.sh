#!/bin/bash

# Runs in the mounted image root as root. Installs the Pi's boot package, which
# brings Raspberry Pi's kernel (linux-rpi) in place of Arch Linux ARM's mainline
# one and U-Boot, and lets it point the kernel command line at the btrfs @
# subvolume, then builds an initramfs that boots any Pi.
#
# mkinitcpio's autodetect would read the build host's hardware here, so the
# image ships an initramfs without it. The boot package's setup-boot asks the
# first boot for a rebuild (/var/lib/omarchy/image/boot-rebuild), which then
# runs on the Pi itself.
#
# Expects /root/pkgs (the omarchy-rpi-boot build).

set -euo pipefail

# btrfs-overlayfs (from limine-snapper-sync) boots read-only snapshots from
# Limine's menu. The Pi's firmware has no such menu, and the hook isn't
# installed. The boot package refuses an encrypted root, and on a plain one the
# encrypt hook only reports, every boot, that the root isn't LUKS. The rest
# only cost build time on a Pi: the command line asks for no splash, so
# plymouth never shows; Omarchy sets no console font, so consolefont finds
# none; and microcode skips itself on aarch64. Without them, the first boot's
# rebuild took 28 s instead of 44 s in the emulated Pi.
cat >/etc/mkinitcpio.conf.d/90-omarchy-pi-boot.conf <<'CONF'
# Written by the Omarchy Pi image build: the firmware boots no snapshots, the
# root isn't encrypted, no splash is shown, no console font is set and no
# microcode loads on a Pi, so drop those hooks from Omarchy's HOOKS baseline
# (00-omarchy-hooks.conf).
_omarchy_pi_hooks=()
for _omarchy_pi_hook in "${HOOKS[@]}"; do
  case $_omarchy_pi_hook in
    btrfs-overlayfs | encrypt | plymouth | consolefont | microcode) ;;
    *) _omarchy_pi_hooks+=("$_omarchy_pi_hook") ;;
  esac
done
HOOKS=("${_omarchy_pi_hooks[@]}")
unset _omarchy_pi_hooks _omarchy_pi_hook

# Arch Linux ARM's mkinitcpio defaults to gzip. The kernel unpacks zstd too,
# and in about half the time.
COMPRESSION=zstd
CONF

# linux-rpi conflicts with linux-aarch64 and uboot-raspberrypi; --ask 4 lets
# pacman remove them.
pacman --noconfirm --disable-sandbox --ask 4 -U --needed /root/pkgs/omarchy-rpi-boot-*.pkg.tar.zst

source /usr/lib/omarchy/rpi-boot/common.sh
point_cmdline_at_root

# Without autodetect, kms would add every GPU driver and its firmware (nvidia
# and amdgpu alone are 240 MB), though the first boot needs none of them before
# the root is mounted: the Pi's own display driver loads from the root, and the
# rebuild on the Pi puts it back in. Leaving kms out took the image's initramfs
# from 169 MB to 27 MB, and its build from 162 s to 62 s in the emulated Pi.
rm -f /etc/pacman.d/hooks/90-mkinitcpio-install.hook
mkinitcpio -k "$(kernel_release)" -S autodetect,kms -g /boot/initramfs-linux.img
