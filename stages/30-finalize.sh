#!/bin/bash

# Runs in the image root as root, last. Arms first-boot owner setup the way a
# deferred-provisioning ISO install does, and strips what only the build
# needed, and the stock accounts: its pacman keyring (each machine makes its own at first boot, asked
# for by /var/lib/omarchy/image/pacman-keyring), the staged packages, and the
# build's resolv.conf. The package cache was the build host's, never the
# image's.

set -euo pipefail

provisioning=/var/lib/omarchy/provisioning
unit=/usr/share/omarchy/install/provisioning/omarchy-provision-owner.service

[[ -x /usr/bin/omarchy-provision-owner && -f $unit ]] || {
  echo "Error: the installed runtime ships no first-boot owner setup" >&2
  exit 1
}

install -d -m 0755 "$provisioning"
touch "$provisioning/pending"
install -m 0644 "$unit" /etc/systemd/system/omarchy-provision-owner.service
install -d /etc/systemd/system/multi-user.target.wants
ln -sfn /etc/systemd/system/omarchy-provision-owner.service /etc/systemd/system/multi-user.target.wants/

# Arch Linux ARM's root ships the alarm account and root with published
# passwords (alarm, root). Owner setup creates the owner and sets root's
# password to the owner's, so the image carries neither.
if id alarm >/dev/null 2>&1; then
  userdel -r alarm 2>/dev/null || userdel alarm
fi
usermod -p '!*' root
echo omarchy >/etc/hostname

rm -rf /etc/pacman.d/gnupg
rm -rf /root/pkgs /root/rpi-pkgs.txt /root/probe.txt

if [[ -e /etc/resolv.conf.image || -L /etc/resolv.conf.image ]]; then
  mv -f /etc/resolv.conf.image /etc/resolv.conf
fi
