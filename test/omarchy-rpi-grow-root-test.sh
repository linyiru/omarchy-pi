#!/bin/bash

# Runs omarchy-rpi-boot's grow-root on a loop device laid out as bin/disk lays
# out a card, a 512 MiB FAT partition and a btrfs root, with the btrfs mounted
# as the Pi mounts its root: written small, then the disk made larger, as an
# image written to a bigger card. Needs sudo and a loop device.
#
# Usage: test/omarchy-rpi-grow-root-test.sh

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script=$here/../packages/omarchy-rpi-boot/lib/grow-root
tmp=$(mktemp -d)
loop=""
cleanup() {
  sudo umount "$tmp/mnt" 2>/dev/null || true
  [[ -z $loop ]] || sudo losetup -d "$loop"
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  echo "not ok - $1" >&2
  [[ -z ${2:-} ]] || printf '%s\n' "$2" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

# Sectors of partition 2 as the kernel sees it, and bytes btrfs has.
partition_sectors() {
  cat "/sys/class/block/${loop#/dev/}/${loop#/dev/}p2/size"
}
btrfs_bytes() {
  sudo btrfs filesystem show --raw "$tmp/mnt" | awk '/devid/ { print $4 }'
}

disk=$tmp/disk.img
truncate -s 1200M "$disk"
sfdisk --quiet "$disk" <<SFDISK
label: dos
start=8MiB, size=512MiB, type=c, bootable
start=520MiB, type=83
SFDISK
loop=$(sudo losetup -fP --show "$disk")
sudo mkfs.vfat -F 32 "${loop}p1" >/dev/null
sudo mkfs.btrfs -q "${loop}p2"
sudo btrfs device scan --forget "${loop}p2" 2>/dev/null || true
mkdir "$tmp/mnt"
sudo mount -o subvol=/ "${loop}p2" "$tmp/mnt"

# At the disk's end already: nothing to do, and nothing written.
before=$(partition_sectors)
out=$(sudo "$script" "$tmp/mnt" 2>&1) || fail "a partition at the end fails" "$out"
[[ -z $out && $(partition_sectors) == "$before" ]] || fail "a partition at the end is left alone" "$out"
pass "a partition at the end is left alone"

# The image on a bigger card.
truncate -s 3000M "$disk"
sudo losetup -c "$loop"
out=$(sudo "$script" "$tmp/mnt" 2>&1) || fail "growing fails" "$out"
expected=$(( (3000 - 520) * 2048 ))
(( $(partition_sectors) == expected )) || fail "the partition reaches the end of the disk" "$(partition_sectors) != $expected"
pass "the partition reaches the end of the disk"
(( $(btrfs_bytes) == expected * 512 )) || fail "btrfs fills the partition" "$(btrfs_bytes) != $(( expected * 512 ))"
pass "btrfs fills the partition"
table=$(sfdisk --dump "$disk")
grep -q 'start=       16384, size=     1048576, type=c, bootable' <<<"$table" || fail "the boot partition is untouched" "$table"
pass "the boot partition is untouched"
[[ $(findmnt -no SOURCE "$tmp/mnt") == "${loop}p2"* ]] || fail "the root stays mounted"
pass "the root stays mounted"

# Run again, as every boot does: nothing more.
out=$(sudo "$script" "$tmp/mnt" 2>&1) || fail "a second run fails" "$out"
[[ -z $out ]] || fail "a second run does nothing" "$out"
pass "a second run does nothing"

# A partition after the root, on a disk with room past it: the root is not
# grown into it.
sudo umount "$tmp/mnt"
sudo losetup -d "$loop"
loop=""
rm "$disk"
truncate -s 3000M "$disk"
sfdisk --quiet "$disk" <<SFDISK
label: dos
start=8MiB, size=512MiB, type=c, bootable
start=520MiB, size=680MiB, type=83
start=1300MiB, size=100MiB, type=83
SFDISK
loop=$(sudo losetup -fP --show "$disk")
sudo mkfs.btrfs -q "${loop}p2"
sudo mount -o subvol=/ "${loop}p2" "$tmp/mnt"
before=$(partition_sectors)
out=$(sudo "$script" "$tmp/mnt" 2>&1) || fail "a following partition fails" "$out"
[[ $out == *"A partition follows"* && $(partition_sectors) == "$before" ]] || fail "a partition that has one after it is left alone" "$out"
pass "a partition that has one after it is left alone"
