#!/usr/bin/env bash
# Hardware probe for arch-hypr.
#
# Standalone: safe to run via `curl <raw-url>/lib/detect.sh | bash` on a live
# USB. Writes nothing; prints key=value lines to stdout and exits 0.
#
# Also sourceable: install.sh loads the functions without running the probe.
# PCI class [0300] is VGA; [0302] is a 3D controller (Optimus / hybrid laptops).
# Matching only "VGA" misses NVIDIA on those machines.

pci_display() {
  command -v lspci >/dev/null 2>&1 || return 0
  lspci -nn 2>/dev/null | grep -E '\[0300\]|\[0302\]' || true
}

has_nvidia() {
  pci_display | grep -qi '\[10de:'
}

has_amd() {
  pci_display | grep -qi '\[1002:'
}

has_intel() {
  pci_display | grep -qi '\[8086:'
}

detect_nproc() {
  nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'
}

detect_root_fs() {
  findmnt -no FSTYPE / 2>/dev/null || printf 'unknown\n'
}

# /boot/grub -> GRUB. /boot/loader -> systemd-boot. Both can exist; report both.
detect_bootloader() {
  local out=()
  [[ -d /boot/grub ]] && out+=(grub)
  [[ -d /boot/loader ]] && out+=(systemd-boot)
  if ((${#out[@]} == 0)); then
    printf 'unknown\n'
  else
    local IFS=+
    printf '%s\n' "${out[*]}"
  fi
}

detect_chassis() {
  local c
  c=$(hostnamectl chassis 2>/dev/null || true)
  c=${c//$'\n'/}
  if [[ -z "$c" ]]; then
    c=$(hostnamectl 2>/dev/null | awk -F: '/Chassis/ {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      print $2
      exit
    }')
  fi
  printf '%s\n' "${c:-unknown}"
}

_bool() {
  if "$1"; then printf '1\n'; else printf '0\n'; fi
}

# Print every detected value as key=value. Never writes a file.
detect_probe() {
  local pci
  pci=$(pci_display | paste -sd '|' -)
  printf 'nproc=%s\n'       "$(detect_nproc)"
  printf 'root_fs=%s\n'     "$(detect_root_fs)"
  printf 'bootloader=%s\n'  "$(detect_bootloader)"
  printf 'chassis=%s\n'     "$(detect_chassis)"
  printf 'nvidia=%s\n'      "$(_bool has_nvidia)"
  printf 'amd=%s\n'         "$(_bool has_amd)"
  printf 'intel=%s\n'       "$(_bool has_intel)"
  printf 'pci=%s\n'         "$pci"
}

# Executed (bash detect.sh, or curl | bash where BASH_SOURCE is empty),
# not when sourced by install.sh.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    --probe|"")
      detect_probe
      exit 0
      ;;
    -h|--help)
      printf 'usage: %s [--probe]\n' "${0##*/}" >&2
      exit 0
      ;;
    *)
      printf 'usage: %s [--probe]\n' "${0##*/}" >&2
      exit 2
      ;;
  esac
fi
