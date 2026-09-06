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

Do not run as root. Modules sudo internally when they touch /etc or pacman.
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

# --- helpers for real module bodies ----------------------------------------

same_file() {
  [[ -e "$1" && -e "$2" && "$1" -ef "$2" ]]
}

# Copy $1 -> $2. Skip if they already resolve to the same inode (self-link
# when this repo IS ~/.config) or if contents already match.
install_file() {
  local src=$1 dest=$2
  mkdir -p "$(dirname -- "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if same_file "$src" "$dest"; then
      say "skip (same file): $dest"
      return 0
    fi
    if [[ -f "$src" || -L "$src" ]] && [[ -f "$dest" || -L "$dest" ]] \
       && cmp -s -- "$src" "$dest"; then
      say "skip (identical): $dest"
      return 0
    fi
  fi
  cp -a -- "$src" "$dest"
  say "copied $src -> $dest"
}

install_link() {
  local src=$1 dest=$2
  mkdir -p "$(dirname -- "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if same_file "$src" "$dest"; then
      say "skip (same file): $dest"
      return 0
    fi
  fi
  ln -sfn -- "$src" "$dest"
  say "linked $dest -> $src"
}

# Recurse files and symlinks under $1 into $2, using install_file.
install_tree() {
  local src=$1 dest=$2
  local f rel
  [[ -d "$src" ]] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    install_file "$f" "$dest/$rel"
  done < <(find "$src" \( -type f -o -type l \) -print0)
}

enable_now() {
  local unit=$1
  if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    say "$unit already enabled"
    return 0
  fi
  say "enable --now $unit"
  sudo systemctl enable --now "$unit"
}

run_00_preflight() {
  say "00-preflight (detect only)"
  echo "  user=$(real_user) home=$(real_home)"
  echo "  root_device=$(root_device)"
  echo "  root_fs=$(detect_root_fs)  bootloader=$(detect_bootloader)  chassis=$(detect_chassis)"
  echo "  nproc=$(detect_nproc)  nvidia=$(_bool has_nvidia) amd=$(_bool has_amd) intel=$(_bool has_intel)"
  echo "  refuse_foreign_disk on anything other than $(root_device)"
  if [[ -n "$HOST" ]]; then
    echo "  --host $HOST (apply host overlay from host/$HOST if present)"
  fi
}

run_10_hypr_stack() {
  say "10-hypr-stack"
  local pkgs=(
    hyprland xdg-desktop-portal-hyprland waybar hyprpaper imv lua jq libnotify
    fuzzel mako grim slurp wl-clipboard yazi pipewire pipewire-pulse wireplumber
    noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd firefox kitty
  )
  say "pacman_needed: ${pkgs[*]}"
  pacman_needed "${pkgs[@]}"
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
    say "no PCI [0300]/[0302] GPU detected — skipping driver packages"
    return 0
  fi
  say "pacman_needed: ${pkgs[*]}"
  pacman_needed "${pkgs[@]}"
}

run_30_dots() {
  say "30-dots"
  local dest_cfg dest_bin src_cfg name
  dest_cfg="$(real_home)/.config"
  dest_bin="$(real_home)/.local/bin"
  src_cfg="$ROOT/config"

  [[ -d "$src_cfg" ]] || fail "config/ missing at $src_cfg"

  mkdir -p "$dest_cfg" "$dest_bin"

  for name in "$src_cfg"/*; do
    [[ -e "$name" ]] || continue
    if [[ -d "$name" ]]; then
      install_tree "$name" "$dest_cfg/$(basename -- "$name")"
    else
      install_file "$name" "$dest_cfg/$(basename -- "$name")"
    fi
  done

  if [[ -n "$HOST" ]]; then
    local overlay="$ROOT/host/$HOST"
    if [[ ! -d "$overlay" ]]; then
      fail "unknown host profile: $HOST (expected $overlay)"
    fi
    if [[ -d "$overlay/hypr" ]]; then
      say "applying host overlay $HOST -> $dest_cfg/hypr"
      install_tree "$overlay/hypr" "$dest_cfg/hypr"
    fi
  fi

  if [[ -x "$dest_cfg/hypr/start-hyprland" ]]; then
    install_link "$dest_cfg/hypr/start-hyprland" "$dest_bin/start-hyprland"
  elif [[ -x "$src_cfg/hypr/start-hyprland" ]]; then
    install_link "$src_cfg/hypr/start-hyprland" "$dest_bin/start-hyprland"
  else
    warn "start-hyprland not found — not linking into $dest_bin"
  fi

  # Scripts live in ~/.config/scripts (hyprland.lua calls them there) and
  # also on PATH: screenshot-watch.service ExecStart=%h/.local/bin/...
  local s
  if [[ -d "$dest_cfg/scripts" ]]; then
    for s in "$dest_cfg/scripts"/*.sh; do
      [[ -e "$s" ]] || continue
      chmod +x "$s"
      install_link "$s" "$dest_bin/$(basename -- "$s")"
    done
    if [[ -f "$dest_cfg/scripts/screenshot-watch.service" ]]; then
      install_link "$dest_cfg/scripts/screenshot-watch.service" \
        "$dest_cfg/systemd/user/screenshot-watch.service"
    fi
  fi
}

run_40_look() {
  say "40-look"
  local dest_state dest_marker src
  dest_state="$(real_home)/.config/hypr/look-state.lua"
  dest_marker="$(real_home)/.config/hypr/current-look"
  src="$ROOT/config/hypr/looks/alpenflage.lua"
  [[ -f "$src" ]] || fail "missing look recipe $src"

  if [[ -e "$dest_state" ]]; then
    say "look-state.lua already exists — not overwriting"
  else
    mkdir -p "$(dirname -- "$dest_state")"
    cp -a -- "$src" "$dest_state"
    say "seeded $dest_state from looks/alpenflage.lua"
  fi
  if [[ -e "$dest_marker" ]]; then
    say "current-look marker already exists — not overwriting"
  else
    printf 'alpenflage\n' > "$dest_marker"
    say "wrote $dest_marker"
  fi
}

run_50_snapshots() {
  say "50-snapshots"
  local fs boot pkgs
  fs=$(detect_root_fs)
  boot=$(detect_bootloader)
  echo "  root_fs=$fs  bootloader=$boot  root_device=$(root_device)"
  refuse_foreign_disk "$(root_device)"
  if [[ "$fs" != btrfs ]]; then
    say "not btrfs — skipping snapper (forced on by --with)"
    return 0
  fi
  pkgs=(snapper snap-pac)
  if [[ "$boot" == *grub* ]]; then
    pkgs+=(grub-btrfs inotify-tools)
    if [[ "${SKIP_LINUX_LTS:-0}" != 1 ]]; then
      pkgs+=(linux-lts linux-lts-headers)
    fi
  fi
  say "pacman_needed: ${pkgs[*]}"
  pacman_needed "${pkgs[@]}"

  if [[ -f /etc/snapper/configs/root ]]; then
    say "snapper config 'root' already exists"
  else
    say "snapper -c root create-config /"
    sudo snapper -c root create-config /
    backup_file /etc/snapper/configs/root
    sudo sed -i -e "s/^ALLOW_USERS=.*/ALLOW_USERS=\"$(real_user)\"/" \
      /etc/snapper/configs/root
  fi

  enable_now snapper-timeline.timer
  enable_now snapper-cleanup.timer

  if [[ "$boot" == *grub* ]]; then
    local unit
    unit=$(systemctl list-unit-files --no-legend 'grub-btrfsd*' | awk '{print $1}' | head -1)
    if [[ -n "$unit" ]]; then
      enable_now "$unit"
    else
      warn "no grub-btrfsd unit found — snapshot boot entries only after grub-mkconfig"
    fi
  else
    say "bootloader is $boot — not enabling grub-btrfsd"
  fi
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
  local n conf rconf overlay
  n=$(detect_nproc)
  conf=/etc/makepkg.conf
  if grep -Eq "^MAKEFLAGS=\"-j${n}\"" "$conf"; then
    say "MAKEFLAGS already -j${n}"
  else
    say "set MAKEFLAGS=-j${n} in $conf"
    backup_file "$conf"
    if grep -q '^MAKEFLAGS=' "$conf"; then
      sudo sed -i "s/^MAKEFLAGS=.*/MAKEFLAGS=\"-j${n}\"/" "$conf"
    elif grep -q '^#MAKEFLAGS=' "$conf"; then
      sudo sed -i "s/^#MAKEFLAGS=.*/MAKEFLAGS=\"-j${n}\"/" "$conf"
    else
      printf 'MAKEFLAGS="-j%s"\n' "$n" | sudo tee -a "$conf" >/dev/null
    fi
  fi

  say "pacman_needed: pacman-contrib reflector"
  pacman_needed pacman-contrib reflector

  enable_now paccache.timer

  rconf=/etc/xdg/reflector/reflector.conf
  overlay=""
  if [[ -n "$HOST" && -f "$ROOT/host/$HOST/reflector.conf" ]]; then
    overlay="$ROOT/host/$HOST/reflector.conf"
  fi
  if [[ -n "$overlay" ]]; then
    if [[ -f "$rconf" ]] && cmp -s -- "$overlay" "$rconf"; then
      say "reflector.conf already matches host overlay"
    else
      say "install reflector.conf from host/$HOST"
      [[ -f "$rconf" ]] && backup_file "$rconf"
      sudo mkdir -p "$(dirname -- "$rconf")"
      sudo cp -- "$overlay" "$rconf"
    fi
  else
    say "no host overlay for reflector --country; leaving $rconf as-is"
  fi

  enable_now reflector.timer
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

say "done"
