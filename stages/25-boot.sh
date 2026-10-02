#!/bin/bash

# Runs in the mounted image root as root. Installs the Pi's boot package and
# lets it point U-Boot's boot script at the btrfs @ subvolume, then builds an
# initramfs that boots any Pi.
#
# mkinitcpio's autodetect would read the build host's hardware here, so the
# image ships an initramfs without it. The boot package's setup-boot asks the
# first boot for a rebuild (/var/lib/omarchy/image/boot-rebuild), which then
# runs on the Pi itself.
#
# Expects /root/pkgs (the omarchy-rpi-boot build).

set -euo pipefail

# btrfs-overlayfs (from limine-snapper-sync) boots read-only snapshots from
# Limine's menu. U-Boot has no such menu, and the hook isn't installed.
cat >/etc/mkinitcpio.conf.d/90-omarchy-pi-boot.conf <<'CONF'
# Written by the Omarchy Pi image build: U-Boot boots no snapshots, so drop the
# snapshot hook from Omarchy's HOOKS baseline (00-omarchy-hooks.conf).
_omarchy_pi_hooks=()
for _omarchy_pi_hook in "${HOOKS[@]}"; do
  [[ $_omarchy_pi_hook == "btrfs-overlayfs" ]] || _omarchy_pi_hooks+=("$_omarchy_pi_hook")
done
HOOKS=("${_omarchy_pi_hooks[@]}")
unset _omarchy_pi_hooks _omarchy_pi_hook
CONF

pacman --noconfirm --disable-sandbox -U --needed /root/pkgs/omarchy-rpi-boot-*.pkg.tar.zst

source /usr/lib/omarchy/rpi-boot/common.sh
point_boot_txt_at_root
build_boot_scr

rm -f /etc/pacman.d/hooks/90-mkinitcpio-install.hook
mkinitcpio -k "$(kernel_release)" -S autodetect -g /boot/initramfs-linux.img
