#!/usr/bin/env bash
# Live-ISO disk helpers. Source after common.sh (needs say/warn/fail).
# Callers own set -e. Used by bootstrap/one-shot-install.sh; live-install.sh
# keeps its own copies so it stays a standalone file.

# /dev/sdb -> /dev/sdb1; /dev/nvme0n1 -> /dev/nvme0n1p1
part_path() {
  local disk=$1 num=$2
  if [[ "$disk" == *[0-9] ]]; then
    printf '%s\n' "${disk}p${num}"
  else
    printf '%s\n' "${disk}${num}"
  fi
}

human_bytes() {
  local b=$1
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B --format='%.1f' "$b"
  else
    awk -v b="$b" 'BEGIN {
      if (b >= 2^30) printf "%.1f GiB\n", b/2^30
      else printf "%.1f MiB\n", b/2^20
    }'
  fi
}

parent_disk_name() {
  local dev=$1 name pk
  name=$(basename -- "$(readlink -f -- "$dev" 2>/dev/null || printf '%s\n' "$dev")")
  if [[ -f "/sys/class/block/${name}/partition" ]]; then
    pk=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1)
    printf '%s\n' "$pk"
  else
    printf '%s\n' "$name"
  fi
}

live_iso_disk() {
  local src
  for src in /run/archiso/bootmnt /run/archiso/copytoram /run/archiso/img_dev; do
    if findmnt -n "$src" >/dev/null 2>&1; then
      parent_disk_name "$(findmnt -no SOURCE "$src")"
      return 0
    fi
  done
  return 1
}

copytoram_active() {
  findmnt -n /run/archiso/copytoram >/dev/null 2>&1
}

mounted_under_ok() {
  # True if every mountpoint of $1 is /mnt, /run/archhypr-* (resume), or
  # /run/archiso/* (the live ISO's own mount of ITS OWN boot disk -- only
  # possible in --force-self mode, since otherwise TARGET != the boot disk
  # and would never show these mountpoints at all).
  local dev=$1 mp
  while IFS= read -r mp; do
    [[ -z "$mp" ]] && continue
    # lsblk can print multiple mountpoints separated by comma or newline.
    IFS=',' read -ra parts <<<"$mp"
    local p
    for p in "${parts[@]}"; do
      p=${p// /}
      [[ -z "$p" || "$p" == "-" ]] && continue
      case "$p" in
        /mnt|/mnt/*|/run/archhypr-*|/run/archiso|/run/archiso/*) ;;
        *) return 1 ;;
      esac
    done
  done < <(lsblk -nr -o MOUNTPOINTS "$dev" 2>/dev/null)
  return 0
}

# Refuse to wipe the live-ISO boot disk unless --force-self and copytoram.
# $1 = canonical whole-disk path, $2 = FORCE_SELF (0/1). Messages match
# bootstrap/live-install.sh so the two gates stay equivalent.
check_force_self() {
  local target=$1 force=${2:-0}
  local tname live
  tname=$(basename -- "$target")
  if live=$(live_iso_disk); then
    if [[ "$tname" == "$live" ]]; then
      if (( force )); then
        if ! copytoram_active; then
          fail "$target is the live ISO boot disk and copytoram is NOT active — --force-self without copytoram=y at boot would wipe the disk out from under the running live system. Reboot with 'copytoram=y' added at the boot menu first."
        fi
        warn "$target is the live ISO boot disk — proceeding because --force-self was passed and copytoram is active"
      else
        fail "$target is the live ISO boot disk — refusing to wipe the installer (pass --force-self if you booted with copytoram=y and mean to reuse this same disk)"
      fi
    fi
  fi
}

# lsblk -o NAME,SIZE,MODEL,TRAN with the live ISO boot disk annotated.
print_lsblk_marked() {
  local live="" name line
  live=$(live_iso_disk 2>/dev/null || true)
  echo
  if ! lsblk -o NAME,SIZE,MODEL,TRAN >/dev/null 2>&1; then
    warn "lsblk failed"
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    name=${line%% *}
    name=${name//[^a-zA-Z0-9_-]/}
    if [[ -n "$live" && "$name" == "$live" ]]; then
      printf '%s  <- you booted from this\n' "$line"
    else
      printf '%s\n' "$line"
    fi
  done < <(lsblk -o NAME,SIZE,MODEL,TRAN)
  echo
  if [[ -n "$live" ]]; then
    say "live ISO boot disk is /dev/${live}  <- you booted from this"
  else
    warn "could not detect the live ISO boot disk (no /run/archiso mount) — compare NAME against the stick you booted"
  fi
}
