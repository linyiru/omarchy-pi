#!/bin/bash

# Fails if a tracked file names a private address, a tailnet, a private key, a
# full-length SSH public key or an email address outside example domains. The
# hardware tests take their machines from the environment; this keeps them
# from leaking back in.
#
# Usage: test/no-private-info-test.sh

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

patterns=(
  '(^|[^0-9.])(10|127)\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)'
  '(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}'
  '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
  '\.ts\.net'
  'BEGIN [A-Z ]*PRIVATE KEY'
  'ssh-(ed25519|rsa) AAAA[A-Za-z0-9+/]{60,}'
)
emails='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
allowed_emails='@(example\.(com|org|net)|users\.noreply\.github\.com)$'

status=0
for pattern in "${patterns[@]}"; do
  if git grep -I -n -E -e "$pattern" -- . ':!test/no-private-info-test.sh'; then
    echo "not ok - a tracked file matches $pattern" >&2
    status=1
  fi
done

while IFS= read -r match; do
  if ! grep -qE "$allowed_emails" <<<"${match##*:}"; then
    echo "$match"
    echo "not ok - a tracked file names an email address" >&2
    status=1
  fi
done < <(git grep -I -n -o -E -e "$emails" -- . ':!test/no-private-info-test.sh' || true)

if (( status == 0 )); then
  echo "ok - no private addresses, keys or email addresses are tracked"
fi
exit "$status"
