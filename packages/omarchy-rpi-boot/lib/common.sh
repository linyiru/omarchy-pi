# Shared by the omarchy-rpi-boot entrypoints; sourced, no shebang.
#
# A Raspberry Pi boots the way Raspberry Pi OS does: the firmware reads
# config.txt from the FAT boot partition, picks the board's device tree and
# overlays, and loads linux-rpi's kernel (kernel8.img) and the initramfs it
# names, with the kernel command line from cmdline.txt. Omarchy's root is the
# btrfs @ subvolume, so cmdline.txt carries its root flags.
#
# This prototype manages unencrypted roots only. Every operation that would
# have to place or drop a boot-time unlock refuses an encrypted one rather than
# leave it unlockable.

set -euo pipefail

boot_dir=/boot
config_txt=$boot_dir/config.txt
cmdline_txt=$boot_dir/cmdline.txt
kernel=$boot_dir/kernel8.img
initramfs=$boot_dir/initramfs-linux.img
root_flags=(rootfstype=btrfs rootflags=subvol=@ rw)
provisioning_dir=/var/lib/omarchy/provisioning

fail() {
  echo "Error: $*" >&2
  exit 1
}

boot_mounted() {
  findmnt -n --target "$boot_dir" -o TARGET | grep -qx "$boot_dir"
}

# An encrypted root shows up as a staged install key, a crypttab for the
# initramfs, or an unlock on the kernel command line.
encrypted_root() {
  [[ -e $provisioning_dir/luks-key || -e /etc/crypttab.initramfs ]] ||
    grep -q 'cryptdevice=\|rd\.luks' "$cmdline_txt" 2>/dev/null
}

refuse_encrypted() {
  if encrypted_root; then
    fail "this omarchy-rpi-boot prototype does not manage encrypted roots"
  fi
}

# The root as fstab names it, by filesystem UUID. The initramfs resolves it, so
# the Pi boots from an SD card or a USB drive alike, and the image build, which
# can't see the disk's devices, writes the same line as the Pi.
root_args() {
  local source
  source=$(findmnt --fstab -n -o SOURCE /) || fail "/etc/fstab has no root entry"
  [[ $source == UUID=* ]] || fail "/etc/fstab names the root as $source, not by UUID"
  echo "root=$source ${root_flags[*]}"
}

cmdline_points_at_root() {
  local args want
  read -r args <"$cmdline_txt" || [[ -n $args ]] || return 1
  for want in $(root_args); do
    [[ " $args " == *" $want "* ]] || return 1
  done
}

# Replaces linux-rpi's default root (root=/dev/mmcblk0p2 rw) and keeps the rest.
point_cmdline_at_root() {
  local args arg line
  if ! cmdline_points_at_root; then
    read -r -a args <"$cmdline_txt" || true
    read -r -a line <<<"$(root_args)"
    for arg in "${args[@]}"; do
      case $arg in
        root=* | rootfstype=* | rootflags=* | rw | ro) ;;
        *) line+=("$arg") ;;
      esac
    done
    echo "${line[*]}" >"$cmdline_txt"
  fi
  cmdline_points_at_root || fail "could not point $cmdline_txt at the @ subvolume"
}

config_loads_initramfs() {
  grep -qx "initramfs ${initramfs##*/} followkernel" "$config_txt"
}

kernel_release() {
  local modules=(/usr/lib/modules/*-rpi)
  (( ${#modules[@]} == 1 )) && [[ -d ${modules[0]} ]] || fail "expected one installed linux-rpi kernel"
  basename "${modules[0]}"
}

# What the firmware loads must be there, and the kernel must be the one whose
# modules are installed.
verify_boot_chain() {
  local root=${1:-} release

  boot_mounted || fail "$boot_dir is not mounted"
  [[ -f $kernel ]] || fail "$kernel is missing"
  [[ -s $initramfs ]] || fail "$initramfs is missing"
  config_loads_initramfs || fail "$config_txt does not load ${initramfs##*/}"
  cmdline_points_at_root || fail "$cmdline_txt does not root on the @ subvolume"

  release=$(kernel_release)
  if ! LC_ALL=C grep -aq "Linux version $release " "$kernel"; then
    fail "$kernel is not kernel $release"
  fi
  if [[ -n $root ]]; then
    [[ -d $root/usr/lib/modules/$release ]] || fail "$root has no modules for kernel $release"
  fi
}
