#!/bin/bash

# Runs in the image root as root. Declares the image a Raspberry Pi build, then
# installs the settings package (it carries the platform guard, which must be
# resident before any platform package), the Pi's default package set and the
# runtime, and runs Omarchy's system setup with provisioning deferred to the
# first boot, as the ISO does for a deferred-provisioning install.
#
# Expects /root/pkgs (local omarchy-dev and omarchy-settings-dev builds) and
# /root/rpi-pkgs.txt (omarchy-pkg-defaults raspberrypi).

set -euo pipefail

# qemu-user implements no Landlock, so pacman's download sandbox can't start
# here. The image's own pacman.conf keeps it.
pacman_build=(pacman --noconfirm --disable-sandbox)

# Prints how long each step took, for bin/build-image's timing summary.
timed() {
  local label=$1 start=$SECONDS
  shift
  "$@"
  echo "TIMING $label $((SECONDS - start))s"
}

install -d -m 0755 /var/lib/omarchy/image
printf 'format=1\nplatform=raspberrypi\n' >/var/lib/omarchy/image/target
chmod 0644 /var/lib/omarchy/image/target

# The ISO's early bootstrap set (orchestrator/phases_impl.py), less its x86
# boot loader: the Arch Linux ARM root lacks base-devel, so it lacks sudo.
# LuaRocks goes in its own transaction before omarchy-nvim, as on the ISO.
# omarchy-dev brings snapper only on x86_64, but install/config/snapper.sh
# runs everywhere, and factory reset rests on the same btrfs layout.
timed bootstrap "${pacman_build[@]}" -S --needed base-devel git omarchy-keyring snapper
timed settings "${pacman_build[@]}" -U --needed /root/pkgs/omarchy-settings-dev-*.pkg.tar.zst
timed luarocks "${pacman_build[@]}" -S --needed lua51 luarocks
timed nvim "${pacman_build[@]}" -S --needed omarchy-nvim
mapfile -t packages </root/rpi-pkgs.txt
timed download "${pacman_build[@]}" -Sw --needed "${packages[@]}"
timed packages "${pacman_build[@]}" -S --needed "${packages[@]}"
timed runtime "${pacman_build[@]}" -U --needed /root/pkgs/omarchy-dev-*.pkg.tar.zst

# snapper create-config cannot make /.snapshots under qemu-user (no btrfs
# ioctls); bin/disk made it, and with a config present install/config/snapper.sh
# installs Omarchy's over it instead of creating one.
if [[ ! -f /etc/snapper/configs/root ]]; then
  install -D -m 0644 /usr/share/omarchy/default/snapper/root /etc/snapper/configs/root
fi

# qemu-user passes no nftables netlink, so iptables cannot even report its
# version, and ufw refuses to edit its rules files without one. An inactive
# ufw touches no kernel tables, so for the setup run only, answer the version
# query and pass anything else through. Restored on exit.
shimmed=()
restore_iptables() {
  local tool
  for tool in "${shimmed[@]}"; do
    mv -f "/usr/bin/$tool.image" "/usr/bin/$tool"
  done
}
trap restore_iptables EXIT
for tool in iptables ip6tables; do
  if ! "$tool" -V >/dev/null 2>&1; then
    version=$(pacman -Q iptables | awk '{print $2}' | cut -d- -f1)
    mv "/usr/bin/$tool" "/usr/bin/$tool.image"
    printf '#!/bin/bash\nif [[ ${1:-} == "-V" || ${1:-} == "--version" ]]; then\n  echo "%s v%s (nf_tables)"\nelse\n  exec -a %s /usr/bin/%s.image "$@"\nfi\n' \
      "$tool" "$version" "$tool" "$tool" >"/usr/bin/$tool"
    chmod 0755 "/usr/bin/$tool"
    shimmed+=("$tool")
  fi
done

export OMARCHY_PATH=/usr/share/omarchy
export OMARCHY_INSTALL=/usr/share/omarchy/install
export OMARCHY_MIRROR=edge
export OMARCHY_INSTALL_LOG_FILE=/var/log/omarchy-install.log
export OMARCHY_LOG_TO_STDOUT=1
timed apply-system /usr/bin/omarchy-apply-system --defer-provisioning --first-install
