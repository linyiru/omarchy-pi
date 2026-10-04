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
quiet_args=(quiet loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0)
provisioning_dir=/var/lib/omarchy/provisioning

# A linux-rpi upgrade boots its kernel once as a trial. The firmware reads
# tryboot.txt instead of config.txt for one boot only, when the reboot asks
# for it, and config.txt boots the last good kernel from fallback/ until the
# trial commits, so a trial that fails falls back on its next reboot. The
# trial's command line adds a reboot on panic, the hardware watchdog and a
# marker the systemd units check.
fallback_dir=$boot_dir/fallback
tryboot_txt=$boot_dir/tryboot.txt
trial_cmdline_txt=$boot_dir/tryboot-cmdline.txt
trial_args=(omarchy.trial panic=5 bcm2835_wdt.nowayout=1 systemd.watchdog_sec=15)
trial_mark="# omarchy-rpi-boot: a trial boot is pending, so boot the last good kernel"
# Left by the shutdown that reboots into the trial, so the boot after it knows
# the trial ran and failed rather than never ran.
trial_attempted=$fallback_dir/attempted
# systemd passes this to the next reboot, whichever asks for it.
reboot_param=/run/systemd/reboot-param

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
  local file=${1:-$cmdline_txt} args want
  read -r args <"$file" || [[ -n $args ]] || return 1
  for want in $(root_args); do
    [[ " $args " == *" $want "* ]] || return 1
  done
}

# Replaces linux-rpi's default root (root=/dev/mmcblk0p2 rw) and keeps the rest,
# adding the quiet console Omarchy boots with on x86
# (etc/limine-entry-tool.d/omarchy-defaults.conf, less the splash, as the Pi has
# no Plymouth). Without it the kernel's messages, such as ufw's logged drops
# and brcmfmac's channel errors, print over first-boot setup on tty1.
# cmdline.txt is a linux-rpi backup file, so upgrades keep the line.
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
    for arg in "${quiet_args[@]}"; do
      [[ " ${line[*]} " == *" $arg "* ]] || line+=("$arg")
    done
    echo "${line[*]}" >"$cmdline_txt"
  fi
  cmdline_points_at_root || fail "could not point $cmdline_txt at the @ subvolume"
}

config_loads_initramfs() {
  grep -qx "initramfs ${initramfs##*/} followkernel" "$config_txt"
}

# The release a kernel image was built as. A trial keeps a second kernel's
# modules installed, so the release comes from the image, not the modules.
image_release() {
  LC_ALL=C grep -aom1 'Linux version [^ ]*' "$1" | cut -d' ' -f3
}

kernel_release() {
  local release
  release=$(image_release "$kernel")
  [[ -n $release ]] || fail "$kernel names no kernel release"
  echo "$release"
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
  [[ -d /usr/lib/modules/$release ]] || fail "$kernel is kernel $release, which has no modules installed"
  if [[ -n $root ]]; then
    [[ -d $root/usr/lib/modules/$release ]] || fail "$root has no modules for kernel $release"
  fi
}

# The firmware booted tryboot.txt.
trial_booted() {
  [[ $(od -An -tx1 /proc/device-tree/chosen/bootloader/tryboot 2>/dev/null | tr -d ' \n') == "00000001" ]]
}

trial_pending() {
  [[ -e $tryboot_txt ]]
}

# The firmware treats a tryboot reboot without tryboot.txt as an unbootable SD
# card and retries it until power is cut, so the reboot asks for a trial only
# while tryboot.txt is in place.
request_trial_reboot() {
  trial_pending || fail "$tryboot_txt is missing, so the reboot can't be a trial"
  printf '0 tryboot' >"$reboot_param"
}

cancel_trial_reboot() {
  if [[ -e $reboot_param ]] && grep -q tryboot "$reboot_param"; then
    rm -f "$reboot_param"
  fi
}

# config.txt as linux-rpi and the owner left it, without the trial's lines.
config_without_trial() {
  awk -v mark="$trial_mark" '$0 == mark { exit } { print }' "$config_txt"
}

# FAT has no journal: write a boot file whole, then move it into place.
replace_boot_file() {
  cat >"$1.new"
  sync "$1.new"
  mv -f "$1.new" "$1"
}

# config.txt boots the kernel in /boot again, and the trial's files go.
end_trial() {
  cancel_trial_reboot
  if grep -qxF "$trial_mark" "$config_txt"; then
    config_without_trial | replace_boot_file "$config_txt"
  fi
  rm -f "$tryboot_txt" "$trial_cmdline_txt"
  rm -rf "$fallback_dir"
  sync -f "$boot_dir"
}

# The trial and its fallback must both boot this system.
verify_trial() {
  local last_good

  grep -qxF "$trial_mark" "$config_txt" || fail "$config_txt does not boot the last good kernel"
  grep -qx "cmdline=${trial_cmdline_txt##*/}" "$tryboot_txt" || fail "$tryboot_txt does not boot the trial's command line"
  cmdline_points_at_root "$trial_cmdline_txt" || fail "$trial_cmdline_txt does not root on the @ subvolume"

  [[ -f $fallback_dir/${kernel##*/} ]] || fail "$fallback_dir has no kernel"
  [[ -s $fallback_dir/${initramfs##*/} ]] || fail "$fallback_dir has no initramfs"
  cmdline_points_at_root "$fallback_dir/${cmdline_txt##*/}" || fail "$fallback_dir/${cmdline_txt##*/} does not root on the @ subvolume"
  last_good=$(image_release "$fallback_dir/${kernel##*/}")
  [[ -n $last_good && -d /usr/lib/modules/$last_good ]] || fail "the last good kernel ${last_good:-in $fallback_dir} has no modules installed"
}
