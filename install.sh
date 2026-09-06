#!/usr/bin/env bash
# arch-hypr installer skeleton.
# Run as yourself, not root — modules sudo internally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$ROOT/lib/detect.sh"
# shellcheck source=lib/pac.sh
source "$ROOT/lib/pac.sh"
# shellcheck source=lib/rootdev.sh
source "$ROOT/lib/rootdev.sh"

ALL_MODULES=(
  00-preflight
  10-hypr-stack
  20-gpu
  30-dots
  40-look
  50-snapshots
  60-suspend
  70-tuning
  80-security
  90-steam
)

HOST=""
PROFILE=""
UNDO=0
WITH=()
WITHOUT=()

usage() {
  cat <<EOF
usage: $0 [options]

  --probe           print hardware key=value lines (also: curl detect.sh | bash)
  --host NAME       host profile name (laptop/desktop/hostname)
  --with X,Y        force-include modules (name or NN-name)
  --without X,Y     exclude modules
  --profile NAME    source bootstrap/NAME-profile.sh (e.g. lite)
  --undo            restore every file recorded in \$MANIFEST_FILE
  -h, --help        this text

Do not run as root. v1 prints the plan and stubs the actions; modules/ and
config/ land in a later pass.
EOF
}

canonical_module() {
  local raw=${1,,}
  raw=${raw// /}
  case "$raw" in
    preflight|00-preflight|00) printf '00-preflight\n' ;;
    hypr-stack|hypr|10-hypr-stack|10) printf '10-hypr-stack\n' ;;
    gpu|20-gpu|20) printf '20-gpu\n' ;;
    dots|30-dots|30) printf '30-dots\n' ;;
    look|40-look|40) printf '40-look\n' ;;
    snapshots|50-snapshots|50) printf '50-snapshots\n' ;;
    suspend|60-suspend|60) printf '60-suspend\n' ;;
    tuning|70-tuning|70) printf '70-tuning\n' ;;
    security|80-security|80) printf '80-security\n' ;;
    steam|90-steam|90) printf '90-steam\n' ;;
    *) fail "unknown module: $1 (try: ${ALL_MODULES[*]})" ;;
  esac
}

split_csv() {
  local csv=$1
  local IFS=,
  # shellcheck disable=SC2086
  set -- $csv
  local p
  for p in "$@"; do
    p=${p#"${p%%[![:space:]]*}"}
    p=${p%"${p##*[![:space:]]}"}
    [[ -n "$p" ]] && printf '%s\n' "$p"
  done
}

in_list() {
  local needle=$1; shift
  local x
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe)
      bash "$ROOT/lib/detect.sh" --probe
      exit 0
      ;;
    --host)
      [[ $# -ge 2 ]] || fail "--host needs a name"
      HOST=$2
      shift 2
      ;;
    --host=*)
      HOST=${1#*=}
      shift
      ;;
    --with)
      [[ $# -ge 2 ]] || fail "--with needs a module list"
      while IFS= read -r m; do
        WITH+=("$(canonical_module "$m")")
      done < <(split_csv "$2")
      shift 2
      ;;
    --with=*)
      while IFS= read -r m; do
        WITH+=("$(canonical_module "$m")")
      done < <(split_csv "${1#*=}")
      shift
      ;;
    --without)
      [[ $# -ge 2 ]] || fail "--without needs a module list"
      while IFS= read -r m; do
        WITHOUT+=("$(canonical_module "$m")")
      done < <(split_csv "$2")
      shift 2
      ;;
    --without=*)
      while IFS= read -r m; do
        WITHOUT+=("$(canonical_module "$m")")
      done < <(split_csv "${1#*=}")
      shift
      ;;
    --profile)
      [[ $# -ge 2 ]] || fail "--profile needs a name"
      PROFILE=$2
      shift 2
      ;;
    --profile=*)
      PROFILE=${1#*=}
      shift
      ;;
    --undo)
      UNDO=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ -n "$PROFILE" ]]; then
  pf="$ROOT/bootstrap/${PROFILE}-profile.sh"
  [[ -f "$pf" ]] || fail "unknown profile: $PROFILE (expected $pf)"
  # shellcheck source=/dev/null
  source "$pf"
  _canon=()
  for m in "${WITHOUT[@]+"${WITHOUT[@]}"}"; do
    _canon+=("$(canonical_module "$m")")
  done
  WITHOUT=("${_canon[@]+"${_canon[@]}"}")
  unset _canon
fi

if [[ "$(id -u)" -eq 0 ]]; then
  fail "do not run as root — rerun as yourself; modules sudo internally"
fi

do_undo() {
  [[ -f "$MANIFEST_FILE" ]] || fail "no manifest at $MANIFEST_FILE"
  say "restoring from $MANIFEST_FILE"
  local lines=() orig bak newest
  mapfile -t lines < "$MANIFEST_FILE"
  local i
  for ((i=${#lines[@]}-1; i>=0; i--)); do
    [[ -n "${lines[i]}" ]] || continue
    orig=${lines[i]%%$'\t'*}
    bak=${lines[i]#*$'\t'}
    if [[ "$bak" == "$orig" || ! -e "$bak" ]]; then
      newest=$(ls -1t -- "$orig".bak.* 2>/dev/null | head -n1 || true)
      bak=$newest
    fi
    if [[ -z "$bak" || ! -e "$bak" ]]; then
      warn "no backup found for $orig — skipping"
      continue
    fi
    say "restore $bak -> $orig"
    if [[ -w "$(dirname -- "$orig")" ]]; then
      cp -a -- "$bak" "$orig"
    else
      sudo cp -a -- "$bak" "$orig"
    fi
  done
  say "undo complete"
}

# --- v1 module bodies: real detection, stubbed actions --------------------

run_00_preflight() {
  say "00-preflight (detect only)"
  echo "  user=$(real_user) home=$(real_home)"
  echo "  root_device=$(root_device)"
  echo "  root_fs=$(detect_root_fs)  bootloader=$(detect_bootloader)  chassis=$(detect_chassis)"
  echo "  nproc=$(detect_nproc)  nvidia=$(_bool has_nvidia) amd=$(_bool has_amd) intel=$(_bool has_intel)"
  echo "  would refuse_foreign_disk on anything other than $(root_device)"
  if [[ -n "$HOST" ]]; then
    echo "  --host $HOST (would apply host profile)"
  fi
}

run_10_hypr_stack() {
  say "10-hypr-stack"
  echo "  would pacman_needed: hyprland xdg-desktop-portal-hyprland waybar hyprpaper imv lua jq libnotify fuzzel mako grim slurp wl-clipboard yazi pipewire pipewire-pulse wireplumber noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd firefox kitty"
}

run_20_gpu() {
  say "20-gpu"
  local pkgs=()
  if has_nvidia; then
    pkgs+=(nvidia-open-dkms nvidia-utils nvidia-settings)
    echo "  nvidia: nvidia-open-dkms (Blackwell needs the open modules, not proprietary)"
  fi
  if has_amd; then
    pkgs+=(mesa vulkan-radeon libva-mesa-driver)
    echo "  amd: mesa + vulkan-radeon"
  fi
  if has_intel; then
    pkgs+=(mesa vulkan-intel intel-media-driver)
    echo "  intel: mesa + vulkan-intel"
  fi
  if ((${#pkgs[@]} == 0)); then
    echo "  no PCI [0300]/[0302] GPU detected — would skip driver packages"
    return 0
  fi
  echo "  would pacman_needed: ${pkgs[*]}"
}

run_30_dots() {
  say "30-dots"
  echo "  would copy/link hyprland.lua, kitty, fish, waybar, fuzzel, mako into $(real_home)/.config"
  echo "  would link start-hyprland into $(real_home)/.local/bin"
  echo "  (config/ is not in this skeleton yet)"
}

run_40_look() {
  say "40-look"
  echo "  would seed $(real_home)/.config/hypr/look-state.lua from looks/alpenflage.lua"
  echo "  would write current-look marker (hyprland.lua dofile()s look-state at parse time)"
}

run_50_snapshots() {
  say "50-snapshots"
  local fs boot pkgs
  fs=$(detect_root_fs)
  boot=$(detect_bootloader)
  echo "  root_fs=$fs  bootloader=$boot  root_device=$(root_device)"
  echo "  would refuse_foreign_disk $(root_device) before creating subvolumes"
  if [[ "$fs" != btrfs ]]; then
    echo "  not btrfs — would skip snapper (forced on by --with)"
  fi
  pkgs=(snapper snap-pac)
  if [[ "$boot" == *grub* ]]; then
    pkgs+=(grub-btrfs inotify-tools)
    if [[ "${SKIP_LINUX_LTS:-0}" != 1 ]]; then
      pkgs+=(linux-lts linux-lts-headers)
    fi
  fi
  echo "  would pacman_needed: ${pkgs[*]}"
}

run_60_suspend() {
  say "60-suspend"
  local boot
  boot=$(detect_bootloader)
  echo "  nvidia=$(_bool has_nvidia)  bootloader=$boot"
  echo "  would add mem_sleep_default=s2idle (Blackwell hangs on deep S3)"
  if [[ "$boot" == *grub* ]]; then
    echo "  would backup_file /etc/default/grub and grub-mkconfig -o /boot/grub/grub.cfg"
  elif [[ "$boot" == *systemd-boot* ]]; then
    echo "  would add the option to /boot/loader/entries/*.conf"
  else
    echo "  bootloader unknown — would print the kernel param and stop"
  fi
}

run_70_tuning() {
  say "70-tuning"
  echo "  would set MAKEFLAGS=-j$(detect_nproc) in /etc/makepkg.conf (backup_file first)"
  echo "  would pacman_needed: pacman-contrib reflector"
  echo "  would enable paccache.timer and reflector.timer"
}

run_80_security() {
  say "80-security"
  echo "  would pacman_needed: ufw clamav arch-audit"
  echo "  would ufw default deny incoming / allow outgoing, enable ufw"
  echo "  would enable clamav-freshclam and a weekly home-scan timer"
}

run_90_steam() {
  say "90-steam"
  local lib32=()
  echo "  would enable_multilib_if_needed"
  if has_nvidia; then
    lib32+=(lib32-nvidia-utils)
  fi
  if has_amd || has_intel; then
    lib32+=(lib32-mesa)
    has_amd && lib32+=(lib32-vulkan-radeon)
    has_intel && lib32+=(lib32-vulkan-intel)
  fi
  if ((${#lib32[@]} == 0)); then
    lib32=(lib32-mesa)
  fi
  echo "  would pacman_needed: steam ${lib32[*]}"
}

run_module() {
  case "$1" in
    00-preflight)  run_00_preflight ;;
    10-hypr-stack) run_10_hypr_stack ;;
    20-gpu)        run_20_gpu ;;
    30-dots)       run_30_dots ;;
    40-look)       run_40_look ;;
    50-snapshots)  run_50_snapshots ;;
    60-suspend)    run_60_suspend ;;
    70-tuning)     run_70_tuning ;;
    80-security)   run_80_security ;;
    90-steam)      run_90_steam ;;
    *) fail "internal: no runner for $1" ;;
  esac
}

plan_modules() {
  local m planned=()
  local fs nvidia
  fs=$(detect_root_fs)
  nvidia=$(_bool has_nvidia)

  for m in "${ALL_MODULES[@]}"; do
    case "$m" in
      50-snapshots)
        [[ "$fs" == btrfs ]] || continue
        ;;
      60-suspend)
        [[ "$nvidia" == 1 ]] || continue
        ;;
    esac
    planned+=("$m")
  done

  for m in "${WITH[@]}"; do
    in_list "$m" "${planned[@]+"${planned[@]}"}" || planned+=("$m")
  done

  local filtered=()
  for m in "${planned[@]}"; do
    in_list "$m" "${WITHOUT[@]+"${WITHOUT[@]}"}" && continue
    filtered+=("$m")
  done

  # Keep ALL_MODULES order even if --with added a skipped module.
  planned=()
  for m in "${ALL_MODULES[@]}"; do
    in_list "$m" "${filtered[@]+"${filtered[@]}"}" && planned+=("$m")
  done
  printf '%s\n' "${planned[@]+"${planned[@]}"}"
}

if [[ "$UNDO" -eq 1 ]]; then
  do_undo
  exit 0
fi

mapfile -t PLAN < <(plan_modules)

echo "arch-hypr plan${HOST:+ (host=$HOST)}${PROFILE:+ (profile=$PROFILE)}:"
if ((${#PLAN[@]} == 0)); then
  echo "  (no modules — everything excluded?)"
  exit 0
fi
for m in "${PLAN[@]}"; do
  echo "  $m"
done
echo

for m in "${PLAN[@]}"; do
  run_module "$m"
done

say "v1 skeleton: no packages installed, no files copied"
say "next pass: modules/ and config/"
