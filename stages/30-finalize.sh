#!/bin/bash

# Runs in the image root as root, last. Arms first-boot owner setup the way a
# deferred-provisioning ISO install does, and strips what only the build
# needed, and the stock accounts: its pacman keyring (each machine makes its own at first boot, asked
# for by /var/lib/omarchy/image/pacman-keyring), the staged packages, and the
# build's resolv.conf. The package cache was the build host's, never the
# image's. Last, it marks the root up to date, so the first boot redoes none of
# the build's work.

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

# The settings Raspberry Pi Imager writes to the card (rpi-preseed.toml) answer
# owner setup and set up Wi-Fi and SSH before it.
pacman --noconfirm --disable-sandbox -U --needed /root/pkgs/omarchy-rpi-preseed-*.pkg.tar.zst

# Arch Linux ARM's root ships the alarm account and root with published
# passwords (alarm, root). Owner setup creates the owner and sets root's
# password to the owner's, so the image carries neither.
if id alarm >/dev/null 2>&1; then
  userdel -r alarm 2>/dev/null || userdel alarm
fi
usermod -p '!*' root
echo omarchy >/etc/hostname

# It also runs systemd-networkd, with DHCP on every wired link (en.network,
# eth.network, owned by no package). Omarchy's network setup retires networkd,
# but only on the first boot, where it ran beside NetworkManager on the same
# link, and only archinstall's network files. Omarchy uses NetworkManager.
systemctl disable systemd-networkd.service systemd-networkd.socket \
  systemd-networkd-varlink.socket systemd-networkd-varlink-metrics.socket \
  systemd-networkd-resolve-hook.socket systemd-networkd-wait-online.service
rm -f /etc/systemd/network/en.network /etc/systemd/network/eth.network

rm -rf /etc/pacman.d/gnupg
rm -rf /root/pkgs /root/rpi-pkgs.txt /root/probe.txt

if [[ -e /etc/resolv.conf.image || -L /etc/resolv.conf.image ]]; then
  mv -f /etc/resolv.conf.image /etc/resolv.conf
fi

# A Pi has no clock without its RTC battery: until the network sets it, the
# first boot runs at systemd's build date, earlier than a signing key made
# since. gpg then refuses that key as made in the future, so the first boot's
# pacman keyring fails (seen 2026-10-05, booting at systemd 262's 2026-09-25).
# systemd starts the clock no earlier than this file's time, the build's.
touch /usr/lib/clock-epoch

# The root has no /etc/.updated or /var/.updated, so the first boot would treat
# /usr as freshly updated and redo, before anything else starts, what the build
# can do now (ldconfig alone took 8 s in the emulated Pi). Run what each
# ConditionNeedsUpdate unit runs, then mark the root current, as
# systemd-update-done.service does. Nothing may change /usr after this.
ldconfig -X
systemd-sysusers
journalctl --update-catalog
if [[ -e /etc/udev/hwdb.bin || -n $(ls -A /etc/udev/hwdb.d 2>/dev/null) ]]; then
  systemd-hwdb update
fi
/usr/lib/systemd/systemd-update-done
