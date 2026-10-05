# SSH with a key only, a German keyboard, and a Wi-Fi network that is saved
# but not there. Owner setup gets a full name, no email.
#
# Sourced by preseed-round, which sets password_hash, ssh_key, wifi_ssid and
# wifi_pmk for the round.

owner_name="Test Owner"

toml() {
  cat <<TOML
config_version = "1.0"

[system]
hostname = "omarchy-test"

[user]
name = "$new_user"
password = "$password_hash"
password_encrypted = true
groups = ["sudo"]
passwordless_sudo = false

[ssh]
enabled = true
password_authentication = false
authorized_keys = [
  "$ssh_key",
]

[wlan]
ssid = "$wifi_ssid"
password = "$wifi_pmk"
password_encrypted = true
hidden = false
country = "DE"

[locale]
keymap = "de"
timezone = "Europe/Berlin"
TOML
}

expect=(
  "hostname=omarchy-test"
  "user=$new_user"
  "user.wheel=yes"
  "user.full-name=Test Owner"
  "git.name=Test Owner"
  "git.email="
  "timezone=Europe/Berlin"
  "keymap.console=de"
  "keymap.desktop=German"
  "ssh.password-authentication=no"
  "ssh.password-login=refused"
  "ssh.port=open"
  "wifi.ssid=$wifi_ssid"
  "wifi.key-mgmt=wpa-psk"
  "wifi.country=DE"
  "preseed-file=removed"
  "provisioning=packages"
  "failed-units=none"
  "root.fills-disk=yes"
)
