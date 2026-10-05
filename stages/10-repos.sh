#!/bin/bash

# Runs in the image root as root. Trusts Arch Linux ARM's and Omarchy's
# signing keys, adds Omarchy's edge repository (the only channel qualified on
# aarch64) and refreshes the package databases. stages/20-install.sh brings
# the root up to date, once bin/build-image has downloaded the packages.
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
# Omarchy publishes its key on keys.openpgp.org, which reset every connection
# to it from home on 2026-10-04; the key is fetched by its full fingerprint, so another
# keyserver can stand in.
if ! pacman-key --recv-keys "$omarchy_key" --keyserver hkps://keys.openpgp.org; then
  pacman-key --recv-keys "$omarchy_key" --keyserver hkps://keyserver.ubuntu.com
fi
pacman-key --lsign-key "$omarchy_key"

if ! grep -qx '\[omarchy\]' /etc/pacman.conf; then
  printf '\n[omarchy]\nServer = https://pkgs.omarchy.org/edge/$arch\n' >>/etc/pacman.conf
fi

# qemu-user implements no Landlock, so pacman's download sandbox can't start.
pacman --noconfirm --disable-sandbox -Sy
