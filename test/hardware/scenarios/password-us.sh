# SSH with password logins (and the key preseed-round logs in with), a US
# keyboard, no Wi-Fi. Owner setup gets an email, no full name.
#
# Sourced by preseed-round, which sets password_hash and ssh_key for the
# round.

owner_email="tester@example.com"

toml() {
  cat <<TOML
config_version = "1.0"

[system]
hostname = "omarchy-test"

[user]
name = "$new_user"
password = "$password_hash"
password_encrypted = true

[ssh]
enabled = true
password_authentication = true
authorized_keys = [
  "$ssh_key",
]

[locale]
keymap = "us"
timezone = "UTC"
TOML
}

expect=(
  "hostname=omarchy-test"
  "user=$new_user"
  "user.wheel=yes"
  "user.full-name="
  "git.name="
  "git.email=tester@example.com"
  "timezone=UTC"
  "keymap.console=us"
  "keymap.desktop=English (US)"
  "ssh.password-authentication=yes"
  "ssh.password-login=accepted"
  "ssh.port=open"
  "wifi.ssid="
  "preseed-file=removed"
  "provisioning=packages"
  "failed-units=none"
)
