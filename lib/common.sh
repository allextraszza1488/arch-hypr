#!/usr/bin/env bash
# Shared helpers. Source only — do not set -e here, callers own the shell.

say()  { printf '==> %s\n' "$*" >&2; }
warn() { printf '[!] %s\n' "$*" >&2; }
fail() { printf '!! %s\n' "$*" >&2; exit 1; }

real_user() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    printf '%s\n' "$SUDO_USER"
  else
    printf '%s\n' "${USER:-$(id -un)}"
  fi
}

real_home() {
  local u
  u=$(real_user)
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    getent passwd "$u" | cut -d: -f6
  else
    printf '%s\n' "${HOME}"
  fi
}

# Prefer the invoking user's state dir so `sudo` does not drop the manifest
# in /root. Callers may override by exporting MANIFEST_FILE first.
if [[ -z "${MANIFEST_FILE:-}" ]]; then
  MANIFEST_FILE="$(real_home)/.local/state/arch-hypr/manifest.txt"
fi
export MANIFEST_FILE

# Copy $1 to $1.bak.TIMESTAMP and append `original<TAB>backup` to the manifest.
# Uses sudo when the destination directory is not writable (e.g. /etc).
backup_file() {
  local src=${1:-}
  [[ -n "$src" ]] || fail "backup_file: missing path"
  [[ -e "$src" ]] || fail "backup_file: $src does not exist"

  local ts bak dir
  ts=$(date +%Y%m%d-%H%M%S)
  bak="${src}.bak.${ts}"
  dir=$(dirname -- "$src")

  if [[ -w "$dir" ]]; then
    cp -a -- "$src" "$bak"
  else
    sudo cp -a -- "$src" "$bak"
  fi

  mkdir -p "$(dirname -- "$MANIFEST_FILE")"
  printf '%s\t%s\n' "$src" "$bak" >> "$MANIFEST_FILE"
  say "backed up $src -> $bak"
}
