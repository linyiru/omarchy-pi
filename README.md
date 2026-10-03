# Omarchy Pi

[![Built for Omarchy](https://raw.githubusercontent.com/tcballard/omarchy-badges/85f859029e236e784e7b05ada6dbe73506d07a91/badges/v1/built-for-omarchy.svg)](https://github.com/tcballard/omarchy-badges)

Builds an Omarchy disk image for the Raspberry Pi from Arch Linux ARM's rpi-aarch64 root, using the Raspberry Pi platform support on the [`raspberry-pi-platform`](https://github.com/linyiru/omarchy/pull/1) branch of Omarchy.

Status: a prototype. The image builds under emulation on an x86_64 host and boots on a Raspberry Pi 5 (16 GB) through first-boot setup. The desktop below needs one more fix that is not in the build yet, applied by hand after first boot (see [Run it on a Raspberry Pi 5](#run-it-on-a-raspberry-pi-5)): the mainline device tree gives the Pi's firmware mailbox no DMA mapping, so the firmware never answers, and without its clocks the GPU and HDMI do not probe. The Pi also sees only 8 GB of its 16 GB.

<img src="docs/pi5-desktop.png" width="1280" alt="Omarchy on a Raspberry Pi 5: fastfetch in a terminal over the Omarchy desktop">

## Build

On Arch Linux, with `sudo`, `qemu-user-static` and `qemu-user-static-binfmt` (x86_64 hosts only), `systemd-nspawn`, `btrfs-progs`, `dosfstools`, `rsync`, `libarchive` and `base-devel`:

```bash
bin/build-image ~/Projects/omarchy ~/Projects/omarchy-pkgs omarchy-pi.img
```

The first argument is an Omarchy checkout with Raspberry Pi support, the second an [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) checkout for the `omarchy-dev` and `omarchy-settings-dev` PKGBUILDs. Downloads go to `~/.cache/omarchy-pi` (`OMARCHY_PI_CACHE`). Write the result to an SD card or USB drive with `dd` or Raspberry Pi Imager's custom image option.

## Run it on a Raspberry Pi 5

Tested on a Raspberry Pi 5 (16 GB) from a microSD card, with HDMI and wired Ethernet.

1. Write the image to the card. Check the device name with `lsblk` first; this overwrites it:

   ```bash
   sudo dd if=omarchy-pi.img of=/dev/sdX bs=4M conv=fsync status=progress
   ```

2. Boot the Pi from the card with a screen, a keyboard and Ethernet attached. The first boot sets up the hardware, rebuilds the initramfs and asks for the owner (user name and password) on tty1. Without the fix below, the screen then stays on the console: there is no desktop yet.

3. Log in on the console, or over SSH once you open its port (`sudo ufw allow 22/tcp`), and give the firmware mailbox its DMA mapping. This installs `dtc` from the network, writes a patched copy of the D0 device tree next to the original, and points `boot.txt` at it:

   ```bash
   sudo pacman -S --needed --noconfirm dtc
   dtc -I dtb -O dts -q -o /tmp/pi5.dts /boot/dtbs/broadcom/bcm2712-d-rpi-5-b.dtb
   cat > /tmp/pi5-mailbox.dts <<'EOF'
   /include/ "/tmp/pi5.dts"

   / {
   	soc@107c000000 {
   		/delete-node/ mailbox@7c013880;
   	};

   	vpu-bus {
   		compatible = "simple-bus";
   		#address-cells = <1>;
   		#size-cells = <1>;
   		ranges = <0x7c000000 0x10 0x7c000000 0x4000000>;
   		dma-ranges = <0xc0000000 0x0 0x0 0x40000000>;

   		vpu_mailbox: mailbox@7c013880 {
   			compatible = "brcm,bcm2835-mbox";
   			reg = <0x7c013880 0x40>;
   			interrupts = <0 33 4>;
   			#mbox-cells = <0>;
   		};
   	};
   };

   &{/firmware/rpi-firmware} {
   	mboxes = <&vpu_mailbox>;
   };
   EOF
   sudo dtc -I dts -O dtb -q -o /boot/dtbs/broadcom/bcm2712-d-rpi-5-b-mailbox.dtb /tmp/pi5-mailbox.dts
   sudo sed -i 's|bcm2712-d-rpi-5-b.dtb|bcm2712-d-rpi-5-b-mailbox.dtb|' /boot/boot.txt
   cd /boot && sudo ./mkscr
   sudo reboot
   ```

4. After the reboot the Omarchy login screen comes up, and the desktop renders on the Pi's V3D GPU. `ls /dev/dri` shows `card0`, `card1` and `renderD128`.

What to know:

- The steps assume a D0 board (every 16 GB Pi 5, and the later smaller ones); `boot.txt` picks the D0 device tree for those by PCB revision. A C1 board uses `bcm2712-rpi-5-b.dtb`, which these steps do not patch.
- A kernel update replaces `bcm2712-d-rpi-5-b.dtb` but not the patched copy, so the Pi boots the new kernel with the old patched tree. Run step 3 again after one.
- Only 8 GB of memory is visible: U-Boot passes the kernel just part of a 16 GB board's memory.
- The root partition stays at the image's size; it is not grown to fill the card.

## Try it in a VM

With `qemu-system-aarch64`, `qemu-hw-display-virtio-gpu-pci`, `qemu-img`, `dtc` and `mtools`:

```bash
bin/run-vm --fresh omarchy-pi.img
bin/vm-qmp screendump screen.png   # the display, also on VNC at 127.0.0.1:5905
bin/vm-qmp key ret                 # keys, or `type <text>` for a line
```

QEMU's `virt` machine stands in for the Pi: its device tree is patched to claim a Raspberry Pi 5, so the first boot takes the Raspberry Pi path, and QEMU loads the kernel and initramfs itself instead of U-Boot. The disk is an overlay on the image, so the image stays as built. What a VM can't test: U-Boot, the Pi's firmware and DTBs, and its devices.

## What the image is

- **Disk:** an MBR with a 512 MiB FAT32 boot partition and a btrfs root holding `@`, `@home`, `@log` and `@pkg`, as an Omarchy ISO install lays them out, plus a read-only `@factory` snapshot for factory reset (`bin/disk`).
- **Boot:** Arch Linux ARM's chain, unchanged: the firmware loads U-Boot (`kernel8.img`), and U-Boot's `boot.scr` loads the mainline `linux-aarch64` kernel, the board's DTB and the initramfs. Only the root flags change, to the `@` subvolume.
- **System:** the Pi's default package set from `omarchy-pkg-defaults raspberrypi`, set up by `omarchy-apply-system --defer-provisioning --first-install` as the ISO does, with hardware setup deferred to the Pi's first boot (`/var/lib/omarchy/image/target` says `platform=raspberrypi`).
- **First boot:** makes the machine's own pacman keyring, runs the deferred hardware setup, rebuilds the initramfs for the board, then asks for the owner on tty1. Owner setup unpacks the Node.js tarball the image carries, so none of it needs the network. The image ships no account: Arch Linux ARM's `alarm` user is removed and root is locked until owner setup.

## Layout

- `bin/build-image` - the whole build
- `bin/build-packages` - builds the Omarchy packages and `packages/` for aarch64 on the host
- `bin/disk` - creates, mounts and snapshots the disk image
- `bin/run-vm`, `bin/vm-qmp` - boot the image in QEMU and drive it
- `stages/` - run inside the image root, in order: repositories, Omarchy, boot, finalization
- `packages/omarchy-rpi-boot` - a prototype of the boot package `omarchy-lifecycle-dispatch` expects on a Pi; unencrypted roots only

## Emulation workarounds

Under qemu-user some things the build needs don't work. Each is confined to the build and to the step that needs it:

- pacman runs with `--disable-sandbox` (no Landlock).
- snapper can't create `/.snapshots` (no btrfs ioctls), so `bin/disk` creates it from the host.
- iptables can't reach nftables (no netfilter netlink), so ufw's version check is answered while it writes its rules files.
- mkinitcpio's autodetect would read the build host, so the image's initramfs is built without it, and the first boot rebuilds it on the Pi.
