#!/bin/bash

# Runs in the image root as root. Trusts Arch Linux ARM's and Omarchy's
# signing keys, adds Omarchy's edge repository (the only channel qualified on
# aarch64) and brings the root up to date.
#
# The keyring made here exists only for the build: the image ships without a
# master key, and each machine makes its own at first boot.

set -euo pipefail

omarchy_key=40DFB630FF42BCFFB047046CF0134EE680CAC571

# Every kernel, firmware or hook package would rebuild the initramfs, slowly
# under emulation and before the boot stage has its configuration. As the ISO
# does during install, mask the build until stages/25-boot.sh runs it once.
install -d /etc/pacman.d/hooks
ln -sfn /dev/null /etc/pacman.d/hooks/90-mkinitcpio-install.hook

pacman-key --init
pacman-key --populate archlinuxarm
pacman-key --recv-keys "$omarchy_key" --keyserver hkps://keys.openpgp.org
pacman-key --lsign-key "$omarchy_key"

if ! grep -qx '\[omarchy\]' /etc/pacman.conf; then
  printf '\n[omarchy]\nServer = https://pkgs.omarchy.org/edge/$arch\n' >>/etc/pacman.conf
fi

# qemu-user implements no Landlock, so pacman's download sandbox can't start.
pacman --noconfirm --disable-sandbox -Syu
