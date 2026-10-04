#!/bin/bash

# Runs omarchy-rpi-preseed against the rpi-preseed.toml Raspberry Pi Imager
# 2.0 writes (src/customization_generator.cpp, generateRpiPreseedToml), in a
# scratch root, with ufw, systemctl and set-wireless-regdom faked and nmcli
# run offline.
#
# Usage: test/omarchy-rpi-preseed-test.sh

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script=$here/../packages/omarchy-rpi-preseed/omarchy-rpi-preseed
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "not ok - $1" >&2
  [[ -z ${2:-} ]] || printf '%s\n' "$2" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

mkdir -p "$tmp/bin"
for tool in ufw systemctl set-wireless-regdom; do
  printf '#!/bin/bash\necho "%s $*" >>"%s/calls"\n' "$tool" "$tmp" >"$tmp/bin/$tool"
  chmod +x "$tmp/bin/$tool"
done

root=$tmp/root
hash='$y$j9T$abcdefghijklmnop$0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef'
pmk=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

# A fresh image root waiting for its owner, with the card's settings.
new_root() {
  rm -rf "$root" "$tmp/calls" "$tmp/out"
  mkdir -p "$root/boot" "$root/var/lib/omarchy/provisioning" "$root/etc/conf.d" "$root/usr/share/systemd"
  touch "$root/var/lib/omarchy/provisioning/pending" "$tmp/calls"
  cp /usr/share/systemd/kbd-model-map "$root/usr/share/systemd/"
  echo 'WIRELESS_REGDOM="US"' >"$root/etc/conf.d/wireless-regdom"
  cat >"$root/boot/rpi-preseed.toml"
}

run() {
  PRESEED_ROOT=$root PATH=$tmp/bin:$PATH "$script" >"$tmp/out" 2>&1
}

answers() {
  cat "$root/var/lib/omarchy/provisioning/answers"
}

keyfile=$root/etc/NetworkManager/system-connections/preconfigured.nmconnection

new_root <<TOML
config_version = "1.0"

[system]
hostname = "pi-desk"

[user]
name = "alice"
password = "$hash"
password_encrypted = true
groups = ["sudo"]
passwordless_sudo = true

[ssh]
enabled = true
password_authentication = false
authorized_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOne alice@laptop",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITwo alice@desk",
]

[wlan]
ssid = "Home \\"5G\\" net"
password = "$pmk"
password_encrypted = true
hidden = true
country = "GB"

[locale]
keymap = "gb"
timezone = "Europe/London"

[interfaces]
i2c = true
TOML
run || fail "a full set of Imager settings applies" "$(cat "$tmp/out")"

expected="hostname=pi-desk
username=alice
timezone=Europe/London
password_hash=$hash
keymap=uk"
[[ $(answers) == "$expected" ]] || fail "owner setup gets the account, hostname, timezone and console keymap" "$(answers)"
[[ $(stat -c %a "$root/var/lib/omarchy/provisioning/answers") == 600 ]] || fail "the answers are the owner's alone"
pass "the account, hostname, timezone and keyboard become owner setup's answers"

[[ $(cat "$root/var/lib/omarchy/provisioning/authorized_keys") == $'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOne alice@laptop\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITwo alice@desk' ]] ||
  fail "both SSH keys are staged" "$(cat "$root/var/lib/omarchy/provisioning/authorized_keys")"
grep -qx "PasswordAuthentication no" "$root/etc/ssh/sshd_config.d/10-omarchy-rpi-preseed.conf" ||
  fail "key-only SSH turns password logins off"
grep -qx "ufw allow 22/tcp" "$tmp/calls" && grep -qx "systemctl enable sshd.service" "$tmp/calls" ||
  fail "SSH is enabled and its port opened" "$(cat "$tmp/calls")"
pass "SSH is enabled for the staged keys, without passwords"

[[ $(stat -c %a "$keyfile") == 600 ]] || fail "the Wi-Fi keyfile is root's alone"
grep -qx 'ssid=Home "5G" net' "$keyfile" && grep -qx "psk=$pmk" "$keyfile" && grep -qx "hidden=true" "$keyfile" &&
  grep -qx "key-mgmt=wpa-psk" "$keyfile" || fail "the hidden network is saved with its key" "$(cat "$keyfile")"
pass "the Wi-Fi network is saved for NetworkManager"

[[ $(cat "$root/etc/conf.d/wireless-regdom") == 'WIRELESS_REGDOM="GB"' ]] ||
  fail "the Wi-Fi country replaces the timezone's" "$(cat "$root/etc/conf.d/wireless-regdom")"
grep -qx "set-wireless-regdom " "$tmp/calls" || fail "the country applies now"
pass "the Wi-Fi country is the one Imager asked for"

[[ ! -e $root/boot/rpi-preseed.toml ]] || fail "the settings file is removed"
grep -q "skipping interfaces.i2c" "$tmp/out" && grep -q "skipping user.passwordless_sudo" "$tmp/out" ||
  fail "what Omarchy doesn't use is logged" "$(cat "$tmp/out")"
pass "the settings file is removed and what Omarchy skips is logged"

new_root <<'TOML'
config_version = "1.0"

[wlan]
ssid_hex = "636166e9"
hidden = false

[locale]
keymap = "ch"
TOML
run || fail "an open network with a hex name applies" "$(cat "$tmp/out")"
grep -qx "ssid=99;97;102;233;" "$keyfile" || fail "a name that isn't UTF-8 is saved as bytes" "$(cat "$keyfile")"
! grep -q "wifi-security" "$keyfile" || fail "an open network has no key" "$(cat "$keyfile")"
[[ $(answers) == "keymap=sg" ]] || fail "a layout with only variants still maps" "$(answers)"
[[ ! -s $tmp/calls ]] || fail "SSH and the country are left alone" "$(cat "$tmp/calls")"
pass "an open network with a hex name, and nothing else, is all that changes"

new_root <<'TOML'
config_version = "1.0"
[user]
name = "bob"
password = "plaintext"
[locale]
keymap = "af"
TOML
run || fail "a plaintext password applies" "$(cat "$tmp/out")"
[[ $(answers) == "username=bob" ]] || fail "only a password hash is staged, only a known layout" "$(answers)"
pass "a password that isn't a hash and a layout with no console keymap are left to owner setup"

new_root <<'TOML'
config_version = "1.0"
[ssh]
enabled = true
authorized_keys = [ "ssh-ed25519 AAAA one"
TOML
if run; then
  fail "an array that never closes is refused"
fi
[[ ! -e $root/boot/rpi-preseed.toml && ! -e $root/var/lib/omarchy/provisioning/answers ]] ||
  fail "a refused file stages nothing and is still removed"
pass "a file this can't read stages nothing and is removed"

new_root <<'TOML'
config_version = "2.0"
[system]
hostname = "future"
TOML
if run; then
  fail "a later major version is refused"
fi
pass "a later config_version is refused"
