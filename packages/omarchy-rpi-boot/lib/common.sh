# Shared by the omarchy-rpi-boot entrypoints; sourced, no shebang.
#
# A Raspberry Pi boots the Arch Linux ARM way: the firmware loads U-Boot
# (kernel8.img) from the FAT boot partition, and U-Boot runs boot.scr, built
# from boot.txt, which loads /Image, the board's DTB and the initramfs and roots
# on partition 2. Omarchy's root is the btrfs @ subvolume, so boot.txt carries
# its root flags.
#
# This prototype manages unencrypted roots only. Every operation that would
# have to place or drop a boot-time unlock refuses an encrypted one rather than
# leave it unlockable.

set -euo pipefail

boot_dir=/boot
boot_txt=$boot_dir/boot.txt
boot_scr=$boot_dir/boot.scr
root_flags="rootfstype=btrfs rootflags=subvol=@"
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
    grep -q 'cryptdevice=\|rd\.luks' "$boot_txt" 2>/dev/null
}

refuse_encrypted() {
  if encrypted_root; then
    fail "this omarchy-rpi-boot prototype does not manage encrypted roots"
  fi
}

boot_txt_points_at_root() {
  grep -q "root=PARTUUID=\${uuid} $root_flags rw" "$boot_txt"
}

point_boot_txt_at_root() {
  if ! boot_txt_points_at_root; then
    sed -i "s|root=PARTUUID=\${uuid} rw|root=PARTUUID=\${uuid} $root_flags rw|" "$boot_txt"
  fi
  boot_txt_points_at_root || fail "could not point $boot_txt at the @ subvolume"
}

# U-Boot 2025.01 names one DTB for every Pi 5, the C1 stepping's. The D0
# stepping (every 16 GB board, and the later smaller ones) moved the pin
# controller's registers, so under that DTB the kernel panics probing it. The
# firmware's own device tree can't tell them apart: it hands U-Boot the C1 one
# on a D0 board too. The PCB revision can, and newer U-Boot picks by it.
d0_dtb=broadcom/bcm2712-d-rpi-5-b.dtb

boot_txt_picks_d0_dtb() {
  grep -q "setenv fdtfile $d0_dtb" "$boot_txt"
}

pick_d0_dtb_in_boot_txt() {
  if ! boot_txt_picks_d0_dtb; then
    sed -i '/^part uuid /r /dev/stdin' "$boot_txt" <<BOOT

# Omarchy Pi: the Pi 5's D0 stepping needs its own device tree. Its PCB
# revision says which stepping it is.
if test "\${board_rev}" = "0x17"; then
  setexpr pcb_rev \${board_revision} "&" 0xf
  if test "\${pcb_rev}" = "1"; then
    setenv fdtfile $d0_dtb
  fi
fi
BOOT
  fi
  boot_txt_picks_d0_dtb || fail "could not make $boot_txt pick the D0 device tree"
  [[ -f $boot_dir/dtbs/$d0_dtb ]] || fail "$boot_dir/dtbs/$d0_dtb is missing"
}

build_boot_scr() {
  mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d "$boot_txt" "$boot_scr" >/dev/null
}

# boot.scr is a 72-byte image header followed by boot.txt.
boot_scr_current() {
  [[ -f $boot_scr ]] && cmp -s <(tail -c +73 "$boot_scr") "$boot_txt"
}

kernel_release() {
  local modules=(/usr/lib/modules/*-aarch64-ARCH)
  (( ${#modules[@]} == 1 )) && [[ -d ${modules[0]} ]] || fail "expected one installed linux-aarch64 kernel"
  basename "${modules[0]}"
}

# What U-Boot loads must be there, and the kernel must be the one whose modules
# are installed.
verify_boot_chain() {
  local root=${1:-} release

  boot_mounted || fail "$boot_dir is not mounted"
  [[ -f $boot_dir/kernel8.img ]] || fail "$boot_dir/kernel8.img (U-Boot) is missing"
  [[ -f $boot_dir/Image ]] || fail "$boot_dir/Image is missing"
  [[ -s $boot_dir/initramfs-linux.img ]] || fail "$boot_dir/initramfs-linux.img is missing"
  [[ -d $boot_dir/dtbs ]] || fail "$boot_dir/dtbs is missing"
  boot_txt_points_at_root || fail "$boot_txt does not root on the @ subvolume"
  boot_txt_picks_d0_dtb || fail "$boot_txt does not pick the Pi 5 D0 device tree"
  [[ -f $boot_dir/dtbs/$d0_dtb ]] || fail "$boot_dir/dtbs/$d0_dtb is missing"
  boot_scr_current || fail "$boot_scr is not built from $boot_txt"

  release=$(kernel_release)
  if ! LC_ALL=C grep -aq "Linux version $release " "$boot_dir/Image"; then
    fail "$boot_dir/Image is not kernel $release"
  fi
  if [[ -n $root ]]; then
    [[ -d $root/usr/lib/modules/$release ]] || fail "$root has no modules for kernel $release"
  fi
}
