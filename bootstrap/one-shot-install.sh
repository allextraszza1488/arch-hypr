#!/usr/bin/env bash
# One-pass Arch + Hyprland installer. Run as root from the live ISO.
# Wipes the target whole disk. No LUKS, no reboot-then-install.sh dance.
#
# Partition: GPT p1 512MiB vfat ESP, p2 rest btrfs with @ and @home.
# Then pacstrap base + the Hyprland stack, copy config/ dots and this
# checkout, create a user, install systemd-boot. After reboot, log in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$ROOT/lib/detect.sh"
# shellcheck source=lib/liveiso.sh
source "$ROOT/lib/liveiso.sh"

ESP_MIB=512
# Smaller than this cannot hold base + Hyprland. No upper bound — this is
# a laptop (or any disk), not the 64GB-USB-only live-install.sh path.
SIZE_MIN=8589934592

SKIPS=()

skip() {
  warn "SKIP: $*"
  SKIPS+=("$*")
}

print_skip_summary() {
  echo
  if ((${#SKIPS[@]} == 0)); then
    say "no non-fatal steps were skipped"
    return 0
  fi
  say "non-fatal skips (${#SKIPS[@]}); the install continued past these:"
  local s
  for s in "${SKIPS[@]}"; do
    printf '    - %s\n' "$s" >&2
  done
}

on_exit() {
  local rc=$?
  print_skip_summary
  if (( rc != 0 )); then
    warn "exited with status $rc — re-run is idempotent for already-written partitions/filesystems"
  fi
}
trap on_exit EXIT

usage() {
  cat <<EOF
usage: $0 [--force-self] [--dry-run] /dev/sdX

Run from the Arch live ISO as root. Wipes the WHOLE disk, then installs
unencrypted Arch + Hyprland in one pass (hostname: archhypr). After reboot,
log in as the created user — Hyprland is ready (tty1 autostarts it).
~/arch-hypr/install.sh is already on disk for later updates.

Pass the WHOLE disk (e.g. /dev/sda, /dev/nvme0n1), never a partition.

--force-self  Allow TARGET to be the same disk the live ISO booted from.
              Only safe if you booted with 'copytoram=y' so the live
              system is fully RAM-resident (check: findmnt should show
              /run/archiso/copytoram as a tmpfs). Without copytoram this
              can crash the live session mid-wipe. Off by default.

--dry-run     Print device list, detection, package plan, and layout.
              Does not prompt, does not write to any disk.

NO encryption. Layout:
  p1  ${ESP_MIB}MiB  EF00  vfat   /boot
  p2  rest           8300  btrfs  @ -> / , @home -> /home
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command '$1' (package: $2)"
}

# ---------- package lists (keep in sync with install.sh) --------------------
# install.sh run_10_hypr_stack
HYPR_PKGS=(
  hyprland xdg-desktop-portal-hyprland waybar hyprpaper imv lua jq libnotify
  fuzzel mako grim slurp wl-clipboard yazi pipewire pipewire-pulse wireplumber
  noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd firefox kitty
)

# Hard-fail if this group cannot be installed. No cryptsetup.
BASE_REQUIRED=(base linux linux-firmware btrfs-progs sudo networkmanager)

# Nice to have; skipped individually on failure.
BASE_OPTIONAL=(base-devel sbctl pciutils)

gpu_packages() {
  # Same branches as install.sh run_20_gpu, plus linux-headers so
  # nvidia-open-dkms can build in the chroot.
  local pkgs=()
  if has_nvidia; then
    pkgs+=(linux-headers nvidia-open-dkms nvidia-utils nvidia-settings)
  fi
  if has_amd; then
    pkgs+=(mesa vulkan-radeon libva-mesa-driver)
  fi
  if has_intel; then
    pkgs+=(mesa vulkan-intel intel-media-driver)
  fi
  if ((${#pkgs[@]} > 0)); then
    printf '%s\n' "${pkgs[@]}"
  fi
}

# ---------- args ------------------------------------------------------------

FORCE_SELF=0
DRY_RUN=0
args=()
for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    --force-self) FORCE_SELF=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]}"
[[ $# -eq 1 ]] || { usage; exit 1; }

if (( ! DRY_RUN )); then
  [[ "$(id -u)" -eq 0 ]] || fail "run as root from the Arch live ISO"
fi

need_cmd sgdisk gptfdisk
need_cmd mkfs.fat dosfstools
need_cmd mkfs.btrfs btrfs-progs
need_cmd btrfs btrfs-progs
need_cmd pacstrap arch-install-scripts
need_cmd genfstab arch-install-scripts
need_cmd arch-chroot arch-install-scripts
need_cmd lsblk util-linux
need_cmd blockdev util-linux
need_cmd blkid util-linux

TARGET=$1
if (( DRY_RUN )); then
  if [[ -b "$TARGET" ]]; then
    TARGET=$(readlink -f -- "$TARGET")
  else
    warn "dry-run: $TARGET is not a block device on this machine — printing the plan anyway"
  fi
else
  [[ -b "$TARGET" ]] || fail "$TARGET is not a block device"
  TARGET=$(readlink -f -- "$TARGET")
  [[ -b "$TARGET" ]] || fail "$TARGET vanished after readlink"
fi

tname=$(basename -- "$TARGET")
if (( ! DRY_RUN )); then
  if [[ -f "/sys/class/block/${tname}/partition" ]]; then
    fail "$TARGET is a partition — pass the whole disk (e.g. /dev/sda, not /dev/sda1)"
  fi
fi

bytes=0
if [[ -b "$TARGET" ]]; then
  bytes=$(blockdev --getsize64 "$TARGET")
  if (( bytes < SIZE_MIN )); then
    fail "$TARGET is $(human_bytes "$bytes") ($bytes bytes); need at least $(human_bytes "$SIZE_MIN"). Wrong disk?"
  fi
fi

if [[ -b "$TARGET" ]]; then
  check_force_self "$TARGET" "$FORCE_SELF"
  if ! mounted_under_ok "$TARGET"; then
    fail "$TARGET has filesystems mounted outside /mnt (unmount them, or you picked the running system)"
  fi
fi

if [[ ! -d /run/archiso ]]; then
  warn "not inside the Arch live ISO (no /run/archiso). Continuing would still wipe $TARGET."
fi

say "block devices — confirm $TARGET is the disk you want to wipe:"
print_lsblk_marked

model=unknown
serial=unknown
tran=unknown
if [[ -b "$TARGET" ]]; then
  model=$(lsblk -dno MODEL "$TARGET" 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//')
  serial=$(lsblk -dno SERIAL "$TARGET" 2>/dev/null | tr -s ' ')
  tran=$(lsblk -dno TRAN "$TARGET" 2>/dev/null | tr -s ' ')
fi

mapfile -t GPU_PKGS < <(gpu_packages)
if command -v lspci >/dev/null 2>&1; then
  say "GPU probe (lib/detect.sh): nvidia=$(_bool has_nvidia) amd=$(_bool has_amd) intel=$(_bool has_intel)"
else
  skip "lspci missing — GPU packages will not be selected"
  GPU_PKGS=()
fi

cat >&2 <<EOF

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  DESTRUCTIVE: this will IRREVERSIBLY WIPE ALL DATA on the device
  below. A typo here installs onto (and erases) the wrong disk.
  NO encryption — anything on $TARGET is gone and unencrypted after.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  device     : $TARGET
  size       : $( [[ $bytes -gt 0 ]] && human_bytes "$bytes" || printf 'unknown' )  ($bytes bytes)
  model      : ${model:-unknown}
  serial     : ${serial:-unknown}
  transport  : ${tran:-unknown}

Current layout:
$(if [[ -b "$TARGET" ]]; then lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,PARTLABEL "$TARGET" | sed 's/^/  /'; else echo '  (device not present on this machine)'; fi)

Planned layout (whole-disk, NO LUKS):
  p1  ${ESP_MIB}MiB  EF00  vfat   /boot
  p2  rest           8300  btrfs  @ -> / , @home -> /home
  no swap partition (zram belongs on the installed system, not this script)

pacstrap required : ${BASE_REQUIRED[*]}
pacstrap optional : ${BASE_OPTIONAL[*]}
hypr stack        : ${HYPR_PKGS[*]}
gpu packages      : ${GPU_PKGS[*]:-(none detected)}
dots              : $ROOT/config -> ~/.config  (per-file skip on failure)
checkout          : $ROOT -> ~/arch-hypr

EOF

if (( DRY_RUN )); then
  say "dry-run: stopping before confirmation / any disk write"
  exit 0
fi

read -r -p "Type 'yes' in full to wipe $TARGET and continue: " confirm
[[ "$confirm" == yes ]] || fail "aborted (typed ${confirm:-nothing}, needed 'yes')"

# Username now, so the rest of the script can run unattended until passwd.
NEWUSER=""
while [[ -z "$NEWUSER" ]]; do
  read -r -p "username for the first non-root account (wheel/sudo): " NEWUSER
  NEWUSER=${NEWUSER// /}
  if [[ ! "$NEWUSER" =~ ^[a-z_][a-z0-9_-]*$ || "$NEWUSER" == root ]]; then
    warn "use a lowercase POSIX name, not 'root'"
    NEWUSER=""
  fi
done

P1=$(part_path "$TARGET" 1)
P2=$(part_path "$TARGET" 2)

# If this checkout lives on TARGET, copy it to RAM before the wipe.
ensure_checkout_off_target() {
  local srcdev srcdisk
  srcdev=$(findmnt -no SOURCE -T "$ROOT" 2>/dev/null || true)
  [[ -n "$srcdev" ]] || return 0
  srcdisk=$(parent_disk_name "$srcdev")
  if [[ -n "$srcdisk" && "$srcdisk" == "$tname" ]]; then
    local safe=/run/archhypr-checkout
    say "this checkout ($ROOT) sits on $TARGET — copying to $safe before wipe"
    rm -rf "$safe"
    mkdir -p "$safe"
    cp -a "$ROOT"/. "$safe"/ || fail "could not copy checkout off $TARGET before wipe"
    ROOT=$safe
  fi
}
ensure_checkout_off_target

# Leftover state from a previous live-install.sh (LUKS) or this script.
if command -v cryptsetup >/dev/null 2>&1 && [[ -e /dev/mapper/cryptroot ]]; then
  warn "closing leftover mapper cryptroot from a previous encrypted install attempt"
  umount -R /mnt 2>/dev/null || true
  cryptsetup close cryptroot || skip "could not close leftover /dev/mapper/cryptroot — mkfs may fail if it still holds $P2"
fi
if is_mounted_on() { findmnt -n "$1" >/dev/null 2>&1; }; then :; fi

is_mounted_on() {
  findmnt -n "$1" >/dev/null 2>&1
}

if is_mounted_on /mnt; then
  say "unmounting leftover /mnt from a previous attempt"
  umount -R /mnt || fail "could not unmount /mnt — unmount it by hand and re-run"
fi

if (( FORCE_SELF )); then
  local_mp
  for local_mp in /run/archiso/bootmnt /run/archiso/img_dev; do
    if findmnt -n "$local_mp" >/dev/null 2>&1; then
      say "lazy-unmount $local_mp so $TARGET can be wiped (copytoram keeps the live system alive)"
      umount -l "$local_mp" || skip "could not unmount $local_mp"
    fi
  done
fi

# ---------- GPT -------------------------------------------------------------

esp_ok=0
data_ok=0
if [[ -b "$P1" && -b "$P2" ]]; then
  p1_type=$(lsblk -no PARTTYPE "$P1" 2>/dev/null | tr '[:upper:]' '[:lower:]')
  p2_type=$(lsblk -no PARTTYPE "$P2" 2>/dev/null | tr '[:upper:]' '[:lower:]')
  p1_bytes=$(blockdev --getsize64 "$P1" 2>/dev/null || echo 0)
  if [[ "$p1_type" == c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] \
     && (( p1_bytes >= 400*1024*1024 && p1_bytes <= 600*1024*1024 )); then
    esp_ok=1
  fi
  # 8300 Linux filesystem, or leftover 8309 Linux LUKS from live-install.sh
  case "$p2_type" in
    0fc63daf-8483-4772-8e79-3d69d8477de4|ca7d7ccb-63bd-4d62-81ec-74878e238d2a)
      data_ok=1 ;;
  esac
fi

if [[ "$esp_ok" -eq 1 && "$data_ok" -eq 1 ]]; then
  say "GPT already has ESP + data partition at expected sizes — skipping sgdisk"
else
  say "sgdisk: zap and write GPT on $TARGET (p1 ESP ${ESP_MIB}MiB, p2 rest, no LUKS)"
  # ISO-hybrid disks (the Arch installer stick itself, and some factory
  # images) make `sgdisk --zap-all` print 'Invalid partition data!' and
  # exit non-zero AFTER a successful wipe. set -e used to kill the whole
  # installer here, before any partitions were created. The zap is
  # best-effort; partition creation below is the hard-fail.
  set +e
  sgdisk --zap-all "$TARGET"
  zap_rc=$?
  set -e
  if (( zap_rc != 0 )); then
    warn "sgdisk --zap-all exited $zap_rc on $TARGET (common on ISO-hybrid / dirty GPT) — continuing to write a new table"
  fi
  wipefs -a "$TARGET" >/dev/null 2>&1 || warn "wipefs -a $TARGET exited non-zero — continuing"
  sgdisk --clear "$TARGET" || fail "sgdisk --clear failed on $TARGET (cannot write a GPT)"
  sgdisk -n "1:0:+${ESP_MIB}M" -t 1:ef00 -c 1:ESP \
         -n 2:0:0              -t 2:8300 -c 2:rootfs \
         "$TARGET" || fail "sgdisk failed to create partitions on $TARGET"
  if ! sgdisk --verify "$TARGET" >/dev/null; then
    warn "sgdisk --verify reported issues on $TARGET — continuing if partition nodes appear"
  fi
  partprobe "$TARGET" 2>/dev/null || warn "partprobe $TARGET failed (often harmless)"
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle || warn "udevadm settle failed"
  fi
  for _ in 1 2 3 4 5; do
    [[ -b "$P1" && -b "$P2" ]] && break
    sleep 1
    partprobe "$TARGET" 2>/dev/null || true
    blockdev --rereadpt "$TARGET" 2>/dev/null || true
  done
  [[ -b "$P1" && -b "$P2" ]] || fail "partition nodes $P1 / $P2 did not appear"
fi

# ---------- filesystems -----------------------------------------------------

p1_fs=$(blkid -s TYPE -o value "$P1" 2>/dev/null || true)
if [[ "$p1_fs" == vfat ]]; then
  say "$P1 already vfat — skipping mkfs.fat"
else
  say "mkfs.fat -F32 $P1"
  mkfs.fat -F32 -n ESP "$P1" || fail "mkfs.fat failed on $P1"
fi

p2_fs=$(blkid -s TYPE -o value "$P2" 2>/dev/null || true)
if [[ "$p2_fs" == btrfs ]]; then
  say "$P2 already btrfs — skipping mkfs.btrfs"
else
  say "mkfs.btrfs -f -L archhypr $P2"
  mkfs.btrfs -f -L archhypr "$P2" || fail "mkfs.btrfs failed on $P2"
fi

top=/run/archhypr-top
mkdir -p "$top"
if is_mounted_on "$top"; then
  umount "$top" || fail "could not unmount $top"
fi
mount "$P2" "$top" || fail "could not mount $P2 on $top to create subvolumes"
if [[ ! -d "$top/@" ]]; then
  say "btrfs subvolume create @"
  btrfs subvolume create "$top/@" || fail "failed to create subvolume @"
else
  say "subvolume @ already exists"
fi
if [[ ! -d "$top/@home" ]]; then
  say "btrfs subvolume create @home"
  btrfs subvolume create "$top/@home" || fail "failed to create subvolume @home"
else
  say "subvolume @home already exists"
fi
umount "$top"
rmdir "$top" 2>/dev/null || true

# ---------- mount @, @home, ESP --------------------------------------------

mkdir -p /mnt
if is_mounted_on /mnt; then
  src=$(findmnt -no SOURCE /mnt)
  fsroot=$(findmnt -no FSROOT /mnt 2>/dev/null || true)
  if [[ "$src" == "$P2" && ( "$fsroot" == /@ || "$fsroot" == @ ) ]]; then
    say "/mnt already has $P2 subvol=@"
  else
    fail "/mnt is mounted from $src (FSROOT=${fsroot:-?}) — unmount it first"
  fi
else
  say "mount -o subvol=@ $P2 /mnt"
  mount -o subvol=@ "$P2" /mnt || fail "could not mount subvol=@ on /mnt"
fi

mkdir -p /mnt/home /mnt/boot
if is_mounted_on /mnt/home; then
  say "/mnt/home already mounted"
else
  say "mount -o subvol=@home $P2 /mnt/home"
  mount -o subvol=@home "$P2" /mnt/home || fail "could not mount subvol=@home on /mnt/home"
fi
if is_mounted_on /mnt/boot; then
  say "/mnt/boot already mounted"
else
  say "mount $P1 /mnt/boot"
  mount "$P1" /mnt/boot || fail "could not mount ESP $P1 on /mnt/boot"
fi

# ---------- pacstrap --------------------------------------------------------

say "pacstrap -K /mnt (${BASE_REQUIRED[*]})"
pacstrap -K /mnt "${BASE_REQUIRED[@]}" || fail "pacstrap of base (${BASE_REQUIRED[*]}) failed — nothing else can proceed"

install_in_target() {
  local p
  (( $# > 0 )) || return 0
  say "install in target: $*"
  if arch-chroot /mnt pacman -S --needed --noconfirm "$@"; then
    return 0
  fi
  warn "group install failed ($*) — retrying one package at a time"
  for p in "$@"; do
    if arch-chroot /mnt pacman -S --needed --noconfirm "$p"; then
      say "installed: $p"
    else
      skip "package '$p' failed to install"
    fi
  done
}

install_in_target "${BASE_OPTIONAL[@]}"
install_in_target "${HYPR_PKGS[@]}"
if ((${#GPU_PKGS[@]} > 0)); then
  install_in_target "${GPU_PKGS[@]}"
else
  say "no PCI [0300]/[0302] GPU detected — skipping driver packages"
fi

# ---------- fstab -----------------------------------------------------------

if [[ -f /mnt/etc/fstab ]] && grep -q 'subvol=/@' /mnt/etc/fstab; then
  say "/mnt/etc/fstab already has btrfs subvol entries — not appending"
else
  say "genfstab -U /mnt >> /mnt/etc/fstab"
  genfstab -U /mnt >> /mnt/etc/fstab || fail "genfstab failed"
fi
grep -q '/boot' /mnt/etc/fstab || fail "/mnt/etc/fstab is missing a /boot entry — not booting this"
grep -Eq '[[:space:]]/[[:space:]]' /mnt/etc/fstab || fail "/mnt/etc/fstab is missing a / entry"

ROOT_UUID=$(blkid -s UUID -o value "$P2" || true)
[[ -n "$ROOT_UUID" ]] || fail "could not read UUID of $P2"

# ---------- chroot: locale, user, bootloader --------------------------------

chroot_script=/mnt/root/.archhypr-chroot.sh
cat > "$chroot_script" <<'CHROOT'
#!/usr/bin/env bash
set -euo pipefail
ROOT_UUID='@ROOT_UUID@'
NEWUSER='@NEWUSER@'

say()  { printf '==> %s\n' "$*" >&2; }
warn() { printf '[!] %s\n' "$*" >&2; }

# --- timezone / locale (EDIT-ME) ------------------------------------------
if [[ ! -L /etc/localtime ]]; then
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi
if [[ ! -f /etc/archhypr-EDIT-ME ]]; then
  cat > /etc/archhypr-EDIT-ME <<'EOM'
EDIT-ME after first boot:
  timedatectl set-timezone Region/City     # currently UTC
  edit /etc/locale.gen, then locale-gen    # currently en_US.UTF-8
  localectl set-keymap us                  # currently us
EOM
fi

if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
fi
locale-gen
if [[ ! -f /etc/locale.conf ]]; then
  printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
fi
if [[ ! -f /etc/vconsole.conf ]]; then
  printf 'KEYMAP=us\n' > /etc/vconsole.conf
fi

printf 'archhypr\n' > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1        localhost
::1              localhost
127.0.1.1        archhypr.localdomain archhypr
EOF

if ! systemctl enable NetworkManager.service; then
  warn "SKIP: systemctl enable NetworkManager.service failed"
fi

# pipewire as a user service for every account (no user session in chroot)
if ! systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service; then
  warn "SKIP: systemctl --global enable pipewire* failed — enable later as the user"
fi

mkdir -p /etc/sudoers.d
if [[ ! -f /etc/sudoers.d/wheel ]]; then
  cat > /etc/sudoers.d/wheel <<'SUDO'
%wheel ALL=(ALL:ALL) ALL
SUDO
  chmod 440 /etc/sudoers.d/wheel
fi
if id "$NEWUSER" >/dev/null 2>&1; then
  say "user $NEWUSER already exists"
  usermod -aG wheel "$NEWUSER"
else
  useradd -m -G wheel -s /bin/bash "$NEWUSER"
  say "set password for $NEWUSER (needed to log in and to sudo)"
  passwd "$NEWUSER"
fi

# No encrypt hook — this install is plaintext btrfs.
mkinitcpio -P

bootctl_ok=0
if bootctl install --esp-path=/boot --graceful; then
  bootctl_ok=1
fi
if [[ ! -d /boot/EFI/systemd && ! -d /boot/EFI/BOOT && ! -d /boot/EFI/Linux ]]; then
  printf '!! bootctl install failed and no EFI files were written\n' >&2
  exit 1
fi
if (( ! bootctl_ok )); then
  warn "SKIP: bootctl install exited non-zero but EFI files exist — pick this disk from the firmware boot menu if it does not appear automatically"
fi

mkdir -p /boot/loader/entries
cat > /boot/loader/loader.conf <<'EOF'
default arch.conf
timeout 3
console-mode max
editor no
EOF

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ rw
EOF

say "chroot steps done (hostname=archhypr, user=$NEWUSER, systemd-boot, no LUKS)"
CHROOT
sed -i \
  -e "s/@ROOT_UUID@/${ROOT_UUID}/g" \
  -e "s/@NEWUSER@/${NEWUSER}/g" \
  "$chroot_script"
chmod 700 "$chroot_script"

say "arch-chroot /mnt (timezone/locale EDIT-ME, hostname, user, bootctl, mkinitcpio)"
arch-chroot /mnt /root/.archhypr-chroot.sh || fail "chroot setup failed"
rm -f /mnt/root/.archhypr-chroot.sh

# ---------- dots + this checkout into the new user's home -------------------

USER_HOME="/mnt/home/${NEWUSER}"
[[ -d "$USER_HOME" ]] || fail "user home $USER_HOME does not exist — useradd failed?"

dest_cfg="$USER_HOME/.config"
dest_bin="$USER_HOME/.local/bin"
src_cfg="$ROOT/config"
mkdir -p "$dest_cfg" "$dest_bin"

copy_one() {
  local src=$1 dest=$2
  mkdir -p "$(dirname -- "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -e "$src" && -e "$dest" && "$src" -ef "$dest" ]]; then
      say "skip (same file): $dest"
      return 0
    fi
    if [[ -f "$src" || -L "$src" ]] && [[ -f "$dest" || -L "$dest" ]] \
       && cmp -s -- "$src" "$dest"; then
      say "skip (identical): $dest"
      return 0
    fi
  fi
  if cp -a -- "$src" "$dest"; then
    say "copied $src -> $dest"
  else
    skip "dotfile copy failed: $src -> $dest"
    return 1
  fi
}

copy_tree() {
  local src=$1 dest=$2
  local f rel
  [[ -d "$src" ]] || { skip "source tree missing: $src"; return 0; }
  mkdir -p "$dest"
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    copy_one "$f" "$dest/$rel" || true
  done < <(find "$src" \( -type f -o -type l \) -print0)
}

if [[ -d "$src_cfg" ]]; then
  say "copying $src_cfg -> $dest_cfg (per-file skip on failure)"
  for name in "$src_cfg"/*; do
    [[ -e "$name" ]] || continue
    if [[ -d "$name" ]]; then
      copy_tree "$name" "$dest_cfg/$(basename -- "$name")"
    else
      copy_one "$name" "$dest_cfg/$(basename -- "$name")" || true
    fi
  done
else
  skip "config/ missing at $src_cfg — Hyprland will start with upstream defaults"
fi

# look-state.lua is dofile()'d by hyprland.lua — without it the compositor
# errors on load. Seed like install.sh run_40_look.
look_src="$src_cfg/hypr/looks/alpenflage.lua"
look_dest="$dest_cfg/hypr/look-state.lua"
look_marker="$dest_cfg/hypr/current-look"
if [[ -f "$look_src" ]]; then
  mkdir -p "$(dirname -- "$look_dest")"
  if [[ -e "$look_dest" ]]; then
    say "look-state.lua already exists — not overwriting"
  else
    copy_one "$look_src" "$look_dest" || true
  fi
  if [[ -e "$look_marker" ]]; then
    say "current-look marker already exists — not overwriting"
  else
    if printf 'alpenflage\n' > "$look_marker"; then
      say "wrote $look_marker"
    else
      skip "could not write $look_marker"
    fi
  fi
else
  skip "missing look recipe $look_src — hyprland.lua will fail to dofile look-state.lua"
fi

link_one() {
  local src=$1 dest=$2
  mkdir -p "$(dirname -- "$dest")"
  if ln -sfn -- "$src" "$dest"; then
    say "linked $dest -> $src"
  else
    skip "symlink failed: $dest -> $src"
  fi
}

# Inside the installed system these paths are under /home/$NEWUSER, not /mnt.
in_home() {
  printf '%s\n' "/home/${NEWUSER}/${1#${USER_HOME}/}"
}

if [[ -x "$dest_cfg/hypr/start-hyprland" ]]; then
  link_one "$(in_home "$dest_cfg/hypr/start-hyprland")" "$(in_home "$dest_bin/start-hyprland")"
elif [[ -x "$src_cfg/hypr/start-hyprland" ]]; then
  copy_one "$src_cfg/hypr/start-hyprland" "$dest_cfg/hypr/start-hyprland" || true
  chmod +x "$dest_cfg/hypr/start-hyprland" 2>/dev/null || true
  link_one "$(in_home "$dest_cfg/hypr/start-hyprland")" "$(in_home "$dest_bin/start-hyprland")"
else
  skip "start-hyprland not found — not linking into ~/.local/bin"
fi

if [[ -d "$dest_cfg/scripts" ]]; then
  for s in "$dest_cfg/scripts"/*.sh; do
    [[ -e "$s" ]] || continue
    chmod +x "$s" || skip "chmod +x failed: $s"
    link_one "$(in_home "$s")" "$(in_home "$dest_bin/$(basename -- "$s")")"
  done
  if [[ -f "$dest_cfg/scripts/screenshot-watch.service" ]]; then
    link_one "$(in_home "$dest_cfg/scripts/screenshot-watch.service")" \
      "$(in_home "$dest_cfg/systemd/user/screenshot-watch.service")"
  fi
fi

# Copy this checkout so install.sh is present after reboot (no git clone).
repo_dest="$USER_HOME/arch-hypr"
if [[ -d "$repo_dest" && "$ROOT" -ef "$repo_dest" ]]; then
  say "checkout already at $repo_dest"
else
  say "copying checkout $ROOT -> $repo_dest"
  mkdir -p "$repo_dest"
  if cp -a "$ROOT"/. "$repo_dest"/; then
    say "checkout copied to $repo_dest"
  else
    skip "failed to copy arch-hypr checkout into $repo_dest — clone it after first boot if you need install.sh"
  fi
fi

# tty1 autostarts Hyprland. tty2 (Ctrl-Alt-F2) is a fallback shell.
bash_profile="$USER_HOME/.bash_profile"
if [[ -e "$bash_profile" ]] && grep -q 'start-hyprland' "$bash_profile"; then
  say "$bash_profile already launches start-hyprland"
else
  cat >> "$bash_profile" <<'EOF'
# arch-hypr one-shot-install: ~/.local/bin on PATH, Hyprland on tty1
export PATH="$HOME/.local/bin:$PATH"
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "${XDG_VTNR:-0}" == 1 ]]; then
  if command -v start-hyprland >/dev/null 2>&1; then
    exec start-hyprland
  fi
fi
EOF
  say "wrote Hyprland autostart to $bash_profile (tty1); use Ctrl-Alt-F2 for a fallback TTY"
fi

if ! arch-chroot /mnt chown -R "${NEWUSER}:${NEWUSER}" "/home/${NEWUSER}"; then
  skip "chown ${NEWUSER} /home/${NEWUSER} failed — fix permissions after first boot"
fi

# ---------- done ------------------------------------------------------------

cat <<EOF

==> unencrypted Arch + Hyprland is on $TARGET
    root UUID $ROOT_UUID  (btrfs subvol=@, no LUKS)

First boot:
  1. reboot  (or: umount -R /mnt && reboot)
  2. remove the Arch ISO if it is a different stick
  3. boot this disk from the firmware boot menu (systemd-boot on the ESP)
  4. log in as ${NEWUSER}  (sudo via wheel)
     tty1 execs start-hyprland; Ctrl-Alt-F2 is a fallback shell
  5. EDIT-ME: timedatectl set-timezone Region/City
              (see /etc/archhypr-EDIT-ME)

This checkout is already at /home/${NEWUSER}/arch-hypr
(so install.sh is present — no git clone). Later updates / extra modules:

  cd ~/arch-hypr
  ./install.sh

Wi-Fi if the graphical session is not up yet: nmtui  (NetworkManager)

EOF
