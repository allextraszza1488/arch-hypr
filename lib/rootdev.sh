#!/usr/bin/env bash
# Root-device helpers. Source after common.sh.
# Stops snapshot/disk scripts from operating on a foreign partition
# (this box shares the NVMe with another OS).

if ! declare -F fail >/dev/null 2>&1; then
  fail() { printf '!! %s\n' "$*" >&2; exit 1; }
fi

# Block device that backs /. Strips the btrfs subvol suffix findmnt adds
# (`/dev/nvme0n1p1[/@]` -> `/dev/nvme0n1p1`) and canonicalizes symlinks.
root_device() {
  local src
  src=$(findmnt -no SOURCE /) || fail "findmnt could not read SOURCE of /"
  src=${src%%\[*}
  if [[ -e "$src" ]]; then
    readlink -f -- "$src"
  else
    printf '%s\n' "$src"
  fi
}

# Fail loudly if $1 is not this install's root device.
refuse_foreign_disk() {
  local target=${1:-}
  [[ -n "$target" ]] || fail "refuse_foreign_disk: missing /dev path"

  local root canon
  root=$(root_device)

  if [[ -e "$target" ]]; then
    canon=$(readlink -f -- "$target")
  else
    fail "refuse_foreign_disk: $target does not exist (this install's root is $root)"
  fi

  if [[ "$canon" != "$root" ]]; then
    fail "refusing $canon — this install's root is $root; other OS disks are off limits"
  fi
}
