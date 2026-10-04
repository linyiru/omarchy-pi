# The install finish screen

An Omarchy ISO install ends with "Installed Omarchy in …" and a "Start Omarchy" button. An image has no installer: its first boot is the install, and on the `raspberry-pi-platform` branch that first boot goes straight from the setup progress bar to the desktop. To show how long a Raspberry Pi takes from a freshly written card to Omarchy, a demo build ends first-boot setup with the same finish screen instead.

<img src="installed-in-0m38s.jpg" width="960" alt="Installed Omarchy in 0m 38s, on a Raspberry Pi 5">

The screenshot is from a Raspberry Pi 5 (16 GB) booting a fresh microSD card with wired Ethernet on 2026-10-03, captured over a KVM at the HDMI output's 1920×1080.

## What the number counts

The finish screen counts the machine's own time and leaves out the time a person spends answering the setup form:

- **To the setup screen:** seconds from the kernel's start to the moment owner setup starts, just before it shows its form, read from `/proc/uptime`. This covers the kernel, the initramfs, systemd and the deferred first-boot hardware setup.
- **Finishing setup:** seconds from the owner's confirmation to the end of setup: creating the user, applying the theme and unpacking the Node.js tarball the image carries.

The firmware's time before the kernel can't be seen from Linux and isn't counted.

Owner setup writes the same split to `/var/log/omarchy-provision-owner.log`. From the card in the screenshot:

```
[2026-10-03 15:06:12] oem-setup: installed Omarchy in 0m 38s (22s to the setup screen, 16s finishing setup)
```

The same boot's journal, in seconds since the kernel started:

| step | at |
|---|---|
| first-boot hardware setup starts | 4.7 |
| first-boot hardware setup done, owner setup starts | 22.8 |
| owner setup done (after the form was answered) | 205.2 |

`systemd-analyze` reported 1.65 s in the kernel for that boot.

## How the demo build does it

Two commits on top of the platform branch, kept off it because the released image goes straight to the desktop:

1. **Mark the boot that retires an image's manifest as its install** (`5da8fd6c`). When `omarchy-provision-hardware` retires the image's manifest on the first boot, it also creates `/run/omarchy-image-first-boot`. The flag lives in `/run`, so it lasts only for that boot.
2. **End an image's first-boot setup with the install's finish screen** (`1aff0b84`). `omarchy-provision-owner` records the uptime when it starts (`SETUP_READY_AT`). When setup finishes and the flag exists, it logs the time, clears the screen, draws the Omarchy logo with "Installed Omarchy in …" under it, and waits on a centred "Start Omarchy" button (`gum confirm`). The desktop starts when the owner presses it.

An ISO install never sets the flag, so it keeps its own finish screen from the installer and its first boot is unchanged.

The commits are on the [`pi-image-finish-screen`](https://github.com/linyiru/omarchy/tree/pi-image-finish-screen) branch of the Omarchy fork.

## Keeping the screen clean

The finish screen and the setup form draw on tty1, so anything the kernel prints there lands on top of them. On the first card, ufw's logged drops and the Wi-Fi driver's `brcmfmac ... set chanspec ... fail, reason -52` printed over the form, because Raspberry Pi's `cmdline.txt` had no `quiet`.

The image now boots with the same console arguments as Omarchy on x86, without `splash` since the Pi has no Plymouth:

```
quiet loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0
```

`point_cmdline_at_root` in `packages/omarchy-rpi-boot/lib/common.sh` adds them when the build rewrites `cmdline.txt`. With them, `/proc/sys/kernel/printk` reads `0 4 1 7` and the console prints no kernel messages; the screenshot's boot had none on screen.

## Building the demo image

Check out `pi-image-finish-screen` from `linyiru/omarchy` in the Omarchy checkout and build as usual. `bin/build-image` copies the checkout as it is, so no push is needed:

```bash
bin/build-image ~/Projects/omarchy ~/Projects/omarchy-pkgs omarchy-pi-finish.img
```

The build took 12 min 10 s on an x86_64 host under emulation.
