# Testing Imager's settings on a real Pi

`test/hardware/preseed-round` checks what a card Raspberry Pi Imager wrote does on a real Raspberry Pi, without writing a card each time. The Pi is factory-reset back to the image's factory snapshot, which asks for its owner again, so a round is: reset, leave the settings a scenario describes as `/boot/rpi-preseed.toml`, reboot, answer owner setup, log in and check. One round takes about two minutes and needs no one at the Pi.

What a `--wipe` round covers is the first boot of the image the card already holds: `omarchy-rpi-preseed`, owner setup and the desktop session it starts. A new build needs a `--card` round, which writes the image to a card in a reader next to the Pi, with the scenario's settings, as Imager would; someone then moves the card to the Pi and powers it on, and the round carries on from the boot. Imager writing the file is not part of either: the scenarios write what Imager 2.0 writes (the same format `test/omarchy-rpi-preseed-test.sh` uses).

## What it needs

- A Pi running the image, reachable by SSH, and a machine next to it with:
- a console, a program taking `shot <file.png>`, `type <text>` and `key enter`, that sees the Pi's screen and types on its keyboard (an IP KVM, for one);
- the Pi's serial console, a program taking `listen <seconds>` and streaming it to stdout (a USB serial adapter on the Pi 5's debug header).

The environment names all three; nothing about the machines is in this repo:

```bash
OMARCHY_PI_HOST=<address> OMARCHY_PI_CONSOLE=<program> OMARCHY_PI_SERIAL=<program> \
  test/hardware/preseed-round --wipe <current-hostname> key-only-de
```

`--wipe` takes the hostname the Pi has now. The reset erases the Pi, so a round checks the name before it starts and stops if it doesn't match.

For a new build, with the card in a reader:

```bash
OMARCHY_PI_HOST=<address> OMARCHY_PI_CONSOLE=<program> OMARCHY_PI_SERIAL=<program> \
  test/hardware/preseed-round --card /dev/sdX omarchy-pi.img key-only-de
```

It erases the whole card, so it refuses a device that is neither removable nor USB, and unmounts the card's partitions first if a desktop automounted them. It writes only the image's allocated blocks (`dd conv=sparse`): what it skips is free space to the image's file systems. Once it says so, move the card to the Pi and power it on; it waits 25 minutes for the boot.

## Accounts and secrets

Every round makes a new account, `tester`, with a random password and a new SSH key, in the scenario's settings. Both are kept for the next round's reset, which runs as that account, in `$XDG_STATE_HOME/omarchy-pi/hardware/<host>/`, readable only by you. The first round logs in with the account the Pi has: set `OMARCHY_PI_USER`, `OMARCHY_PI_SSH_KEY` (a private key file) and `OMARCHY_PI_PASSWORD_FILE` (its password, for sudo).

Scenarios hold no secrets and no one's details: the password hash, the key and the Wi-Fi key are filled in for each round, and names, hostnames and timezones are made-up ones. The Wi-Fi network a scenario saves is not one that exists, so a round checks it is saved, not that it connects.

The serial log, the screenshots and the checks go to `$OMARCHY_PI_CACHE/hardware/<time>/` (`~/.cache/omarchy-pi` by default). The serial log holds the Pi's machine-id and boot ids: keep these out of the repo. `test/no-private-info-test.sh` fails if a tracked file names a private address, a tailnet, a private key, a full SSH key or an email address outside example domains.

## Scenarios

A scenario under `test/hardware/scenarios/` is bash that preseed-round sources: a `toml` function printing the settings, what owner setup is given (`owner_name`, `owner_email`), and `expect`, the `key=value` lines the round checks. `test/hardware/probe` lists the keys.

- `key-only-de` - SSH with a key only, a German keyboard, a saved Wi-Fi network and its country; a full name, no email
- `password-us` - SSH with password logins, a US keyboard, no Wi-Fi; an email, no full name

The console types as a US keyboard whatever layout the Pi has. With any other layout, keep what a scenario types to letters, digits and spaces, minus the letters the layout moves (`y` and `z` on a German one).
