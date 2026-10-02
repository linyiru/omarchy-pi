#!/bin/bash

# Runs in the image root: prints each name in the package list given as $1
# that no configured repository provides, as a package, group or provider.

set -uo pipefail

while IFS= read -r package; do
  [[ -n $package ]] || continue
  if ! pacman -Sp --print-format %n "$package" >/dev/null 2>&1 && ! pacman -Sg "$package" >/dev/null 2>&1; then
    echo "$package"
  fi
done <"$1"
