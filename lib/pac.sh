#!/usr/bin/env bash
# pacman wrappers. Source after common.sh.

_pac_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Install packages that are not already present. Never a partial upgrade.
pacman_needed() {
  (( $# > 0 )) || fail "pacman_needed: no packages given"
  _pac_root pacman -S --needed --noconfirm "$@"
}

# Uncomment the [multilib] stanza in /etc/pacman.conf if it is still hashed
# out. Idempotent: grep before sed. -Syu runs only on the transition from
# disabled -> enabled, because the sync databases have to agree with the new
# repo list. A bare -Sy is a partial upgrade and is not used.
enable_multilib_if_needed() {
  local conf=/etc/pacman.conf

  if grep -q '^\[multilib\]' "$conf"; then
    say "multilib already enabled"
    return 0
  fi

  grep -q '^#\[multilib\]' "$conf" \
    || fail "no #[multilib] section in $conf — cannot enable it"

  say "enabling multilib in $conf"
  backup_file "$conf"
  # Exact ^#[multilib]$ so [multilib-testing] stays commented.
  _pac_root sed -i \
    '/^#\[multilib\]$/,/^#Include = \/etc\/pacman.d\/mirrorlist$/{s/^#//}' \
    "$conf"

  grep -q '^\[multilib\]' "$conf" \
    || fail "sed ran but [multilib] is still commented in $conf"

  say "pacman -Syu (multilib just enabled; databases must agree)"
  _pac_root pacman -Syu --noconfirm
}
