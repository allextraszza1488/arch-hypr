#!/usr/bin/env bash
# Bootstrap a portable Arch base onto a blank ~64GB USB, from the live ISO.
# Run as root. Wipes the target whole disk. Does NOT run install.sh.
set -euo pipefail

MAPPER=cryptroot
ESP_MIB=512
# Marketing "64GB" sticks land anywhere from ~58GB to 64GiB.
SIZE_MIN=50000000000
SIZE_MAX=72000000000

say()  { printf '==> %s\n' "$*" >&2; }
warn() { printf '[!] %s\n' "$*" >&2; }
fail() { printf '!! %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
usage: $0 /dev/sdX

Run from the Arch live ISO as root. Wipes the whole disk, then installs a
minimal LUKS2+btrfs+systemd-boot Arch base (hostname: archhypr). After
reboot, log in as the created user and run arch-hypr/install.sh.

Pass the WHOLE disk (e.g. /dev/sdb, /dev/nvme1n1), never a partition.
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command '$1' (package: $2)"
}

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
  name=$(basename -- "$(readlink -f -- "$dev")")
  if [[ -f "/sys/class/block/${name}/partition" ]]; then
    pk=$(lsblk -no PKNAME "$dev" | head -n1)
    printf '%s\n' "$pk"
  else
    printf '%s\n' "$name"
  fi
}

is_mounted_on() {
  findmnt -n "$1" >/dev/null 2>&1
}

mounted_under_ok() {
  # True if every mountpoint of $1 is /mnt or /run/archhypr-* (resume).
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
        /mnt|/mnt/*|/run/archhypr-*) ;;
        *) return 1 ;;
      esac
    done
  done < <(lsblk -nr -o MOUNTPOINTS "$dev" 2>/dev/null)
  return 0
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

# ---------- args / preflight ------------------------------------------------

[[ $# -eq 1 ]] || { usage; exit 1; }
[[ "$1" != -h && "$1" != --help ]] || { usage; exit 0; }

[[ "$(id -u)" -eq 0 ]] || fail "run as root from the Arch live ISO"

need_cmd sgdisk gptfdisk
need_cmd mkfs.fat dosfstools
need_cmd cryptsetup cryptsetup
need_cmd mkfs.btrfs btrfs-progs
need_cmd btrfs btrfs-progs
need_cmd pacstrap arch-install-scripts
need_cmd genfstab arch-install-scripts
need_cmd arch-chroot arch-install-scripts
need_cmd lsblk util-linux
need_cmd blockdev util-linux
need_cmd blkid util-linux

TARGET=$1
[[ -b "$TARGET" ]] || fail "$TARGET is not a block device"
TARGET=$(readlink -f -- "$TARGET")
[[ -b "$TARGET" ]] || fail "$TARGET vanished after readlink"

tname=$(basename -- "$TARGET")
if [[ -f "/sys/class/block/${tname}/partition" ]]; then
  fail "$TARGET is a partition — pass the whole disk (e.g. /dev/sdb, not /dev/sdb1)"
fi

bytes=$(blockdev --getsize64 "$TARGET")
if (( bytes < SIZE_MIN || bytes > SIZE_MAX )); then
  fail "$TARGET is $(human_bytes "$bytes") ($bytes bytes); expected a ~64GB stick (${SIZE_MIN}–${SIZE_MAX} bytes). Wrong disk?"
fi

if live=$(live_iso_disk); then
  if [[ "$tname" == "$live" ]]; then
    fail "$TARGET is the live ISO boot disk — refusing to wipe the installer"
  fi
fi

if ! mounted_under_ok "$TARGET"; then
  fail "$TARGET has filesystems mounted outside /mnt (unmount them, or you picked the running system)"
fi

if [[ ! -d /run/archiso ]]; then
  warn "not inside the Arch live ISO (no /run/archiso). Continuing would still wipe $TARGET."
fi

model=$(lsblk -dno MODEL "$TARGET" 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//')
serial=$(lsblk -dno SERIAL "$TARGET" 2>/dev/null | tr -s ' ')
tran=$(lsblk -dno TRAN "$TARGET" 2>/dev/null | tr -s ' ')

cat >&2 <<EOF

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  DESTRUCTIVE: this will IRREVERSIBLY WIPE ALL DATA on the device
  below. A typo here installs onto (and erases) the wrong disk.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  device     : $TARGET
  size       : $(human_bytes "$bytes")  ($bytes bytes)
  model      : ${model:-unknown}
  serial     : ${serial:-unknown}
  transport  : ${tran:-unknown}

Current layout:
$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,PARTLABEL "$TARGET" | sed 's/^/  /')

Planned layout (whole-disk):
  p1  ${ESP_MIB}MiB  EF00  vfat   /boot          (unencrypted ESP)
  p2  rest           8309  LUKS2 -> mapper ${MAPPER}
                     btrfs  @     -> /
                     btrfs  @home -> /home
  no swap partition (zram on the installed system, not this script)

Type 'yes' in full to wipe $TARGET and continue.
EOF

read -r -p "yes/N: " confirm
[[ "$confirm" == yes ]] || fail "aborted (typed ${confirm:-nothing}, needed 'yes')"

P1=$(part_path "$TARGET" 1)
P2=$(part_path "$TARGET" 2)

# ---------- (b) GPT ---------------------------------------------------------

esp_ok=0
luks_part_ok=0
if [[ -b "$P1" && -b "$P2" ]]; then
  p1_type=$(lsblk -no PARTTYPE "$P1" 2>/dev/null | tr '[:upper:]' '[:lower:]')
  p2_type=$(lsblk -no PARTTYPE "$P2" 2>/dev/null | tr '[:upper:]' '[:lower:]')
  p1_bytes=$(blockdev --getsize64 "$P1" 2>/dev/null || echo 0)
  # ESP GUID c12a7328-... ; 400–600 MiB is "close to 512MiB"
  if [[ "$p1_type" == c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] \
     && (( p1_bytes >= 400*1024*1024 && p1_bytes <= 600*1024*1024 )); then
    esp_ok=1
  fi
  # 8309 Linux LUKS, or 8300 Linux filesystem if someone formatted first
  case "$p2_type" in
    ca7d7ccb-63bd-4d62-81ec-74878e238d2a|0fc63daf-8483-4772-8e79-3d69d8477de4)
      luks_part_ok=1 ;;
  esac
fi

if [[ "$esp_ok" -eq 1 && "$luks_part_ok" -eq 1 ]]; then
  say "GPT already has ESP + data partition at expected sizes — skipping sgdisk"
else
  say "sgdisk: zap and write GPT on $TARGET (p1 ESP ${ESP_MIB}MiB, p2 rest)"
  sgdisk --zap-all "$TARGET"
  sgdisk -n "1:0:+${ESP_MIB}M" -t 1:ef00 -c 1:ESP \
         -n 2:0:0              -t 2:8309 -c 2:cryptroot \
         "$TARGET"
  sgdisk --verify "$TARGET" >/dev/null
  partprobe "$TARGET" 2>/dev/null || true
  command -v udevadm >/dev/null && udevadm settle || true
  # nodes can lag on USB
  for _ in 1 2 3 4 5; do
    [[ -b "$P1" && -b "$P2" ]] && break
    sleep 1
    partprobe "$TARGET" 2>/dev/null || true
  done
  [[ -b "$P1" && -b "$P2" ]] || fail "partition nodes $P1 / $P2 did not appear"
fi

# ---------- (c) ESP filesystem ----------------------------------------------

p1_fs=$(blkid -s TYPE -o value "$P1" 2>/dev/null || true)
if [[ "$p1_fs" == vfat ]]; then
  say "$P1 already vfat — skipping mkfs.fat"
else
  say "mkfs.fat -F32 $P1"
  mkfs.fat -F32 -n ESP "$P1"
fi

# ---------- (d) LUKS2 -------------------------------------------------------

if cryptsetup isLuks --type luks2 "$P2" 2>/dev/null \
   || cryptsetup isLuks "$P2" 2>/dev/null; then
  say "$P2 already LUKS — skipping luksFormat (passphrase prompt for open only)"
else
  say "cryptsetup luksFormat --type luks2 $P2 (passphrase prompt; not accepted as a CLI arg)"
  cryptsetup luksFormat --type luks2 --label archhypr "$P2"
fi

if [[ -e "/dev/mapper/${MAPPER}" ]]; then
  say "mapper ${MAPPER} already open"
else
  say "cryptsetup open $P2 ${MAPPER}"
  cryptsetup open "$P2" "$MAPPER"
fi
[[ -b "/dev/mapper/${MAPPER}" ]] || fail "mapper /dev/mapper/${MAPPER} did not appear"

LUKS_UUID=$(cryptsetup luksUUID "$P2")
[[ -n "$LUKS_UUID" ]] || fail "could not read LUKS UUID of $P2"

# ---------- (e) btrfs + subvolumes ------------------------------------------

mapper=/dev/mapper/${MAPPER}
top=/run/archhypr-top
mkdir -p "$top"

mapper_fs=$(blkid -s TYPE -o value "$mapper" 2>/dev/null || true)
if [[ "$mapper_fs" == btrfs ]]; then
  say "$mapper already btrfs — skipping mkfs.btrfs"
else
  say "mkfs.btrfs -L archhypr $mapper"
  mkfs.btrfs -f -L archhypr "$mapper"
fi

if is_mounted_on "$top"; then
  umount "$top"
fi
mount "$mapper" "$top"
if [[ ! -d "$top/@" ]]; then
  say "btrfs subvolume create @"
  btrfs subvolume create "$top/@"
else
  say "subvolume @ already exists"
fi
if [[ ! -d "$top/@home" ]]; then
  say "btrfs subvolume create @home"
  btrfs subvolume create "$top/@home"
else
  say "subvolume @home already exists"
fi
umount "$top"
rmdir "$top" 2>/dev/null || true

# ---------- (f) mount @, @home, ESP -----------------------------------------

mkdir -p /mnt
if is_mounted_on /mnt; then
  src=$(findmnt -no SOURCE /mnt)
  fsroot=$(findmnt -no FSROOT /mnt 2>/dev/null || true)
  if [[ "$src" == "$mapper" && ( "$fsroot" == /@ || "$fsroot" == @ ) ]]; then
    say "/mnt already has ${MAPPER} subvol=@"
  else
    fail "/mnt is mounted from $src (FSROOT=${fsroot:-?}) — unmount it first"
  fi
else
  say "mount -o subvol=@ $mapper /mnt"
  mount -o subvol=@ "$mapper" /mnt
fi

mkdir -p /mnt/home /mnt/boot
if is_mounted_on /mnt/home; then
  say "/mnt/home already mounted"
else
  say "mount -o subvol=@home $mapper /mnt/home"
  mount -o subvol=@home "$mapper" /mnt/home
fi
if is_mounted_on /mnt/boot; then
  say "/mnt/boot already mounted"
else
  say "mount $P1 /mnt/boot"
  mount "$P1" /mnt/boot
fi

# ---------- (g) pacstrap ----------------------------------------------------

say "pacstrap -K /mnt (base + encrypt-needed cryptsetup)"
# cryptsetup is not in the original package sentence but the encrypt hook
# will not boot without it in the target.
pacstrap -K /mnt \
  base base-devel linux linux-firmware \
  btrfs-progs sudo networkmanager sbctl \
  cryptsetup

# ---------- (h) fstab -------------------------------------------------------

if [[ -f /mnt/etc/fstab ]] && grep -q 'subvol=/@' /mnt/etc/fstab; then
  say "/mnt/etc/fstab already has btrfs subvol entries — not appending"
else
  say "genfstab -U /mnt >> /mnt/etc/fstab"
  genfstab -U /mnt >> /mnt/etc/fstab
fi

# ---------- (i) chroot ------------------------------------------------------

say "username for the first non-root account (wheel/sudo)"
NEWUSER=""
while [[ -z "$NEWUSER" ]]; do
  read -r -p "username: " NEWUSER
  NEWUSER=${NEWUSER// /}
  if [[ ! "$NEWUSER" =~ ^[a-z_][a-z0-9_-]*$ || "$NEWUSER" == root ]]; then
    warn "use a lowercase POSIX name, not 'root'"
    NEWUSER=""
  fi
done

chroot_script=/mnt/root/.archhypr-chroot.sh
cat > "$chroot_script" <<'CHROOT'
#!/usr/bin/env bash
set -euo pipefail
LUKS_UUID='@LUKS_UUID@'
MAPPER='@MAPPER@'
NEWUSER='@NEWUSER@'

say() { printf '==> %s\n' "$*" >&2; }

# --- timezone / locale (EDIT-ME) ------------------------------------------
# EDIT-ME: replace UTC with your Region/City, e.g. America/Chicago
if [[ ! -L /etc/localtime ]]; then
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi
# Keep UTC if the symlink is already present (re-run). Do not overwrite a
# later timedatectl change.
if [[ ! -f /etc/archhypr-EDIT-ME ]]; then
  cat > /etc/archhypr-EDIT-ME <<'EOM'
EDIT-ME after first boot:
  timedatectl set-timezone Region/City     # currently UTC
  edit /etc/locale.gen, then locale-gen    # currently en_US.UTF-8
  localectl set-keymap us                  # currently us
EOM
fi

if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
  # EDIT-ME: uncomment additional locales in /etc/locale.gen
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
fi
locale-gen
if [[ ! -f /etc/locale.conf ]]; then
  printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf   # EDIT-ME
fi
if [[ ! -f /etc/vconsole.conf ]]; then
  printf 'KEYMAP=us\n' > /etc/vconsole.conf         # EDIT-ME
fi

# --- hostname --------------------------------------------------------------
printf 'archhypr\n' > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1        localhost
::1              localhost
127.0.1.1        archhypr.localdomain archhypr
EOF

systemctl enable NetworkManager.service

# --- sudo + user -----------------------------------------------------------
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

# --- mkinitcpio encrypt hook (before filesystems; after block) ------------
if grep -E '^[[:space:]]*HOOKS=' /etc/mkinitcpio.conf | grep -qw encrypt; then
  say "mkinitcpio HOOKS already contains encrypt"
else
  # Insert 'encrypt' immediately after 'block'. The encrypt hook requires
  # that order; putting it after filesystems means the mapper is not open
  # when fsck/mount run.
  sed -i -E 's/(HOOKS=\([^)]*\bblock)\b/\1 encrypt/' /etc/mkinitcpio.conf
  if ! grep -E '^[[:space:]]*HOOKS=' /etc/mkinitcpio.conf | grep -qw encrypt; then
    printf '!! failed to insert encrypt into HOOKS\n' >&2
    exit 1
  fi
fi
mkinitcpio -P

# --- systemd-boot ----------------------------------------------------------
bootctl install --esp-path=/boot --graceful

cat > /boot/loader/loader.conf <<'EOF'
default arch.conf
timeout 3
console-mode max
editor no
EOF

# cryptdevice=  -> mkinitcpio encrypt hook
# rd.luks.name= -> sd-encrypt (harmless alongside encrypt; kept as specified)
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options cryptdevice=UUID=${LUKS_UUID}:${MAPPER} rd.luks.name=${LUKS_UUID}=${MAPPER} root=/dev/mapper/${MAPPER} rootflags=subvol=@ rw
EOF

say "chroot steps done (hostname=archhypr, user=$NEWUSER, systemd-boot, encrypt hook)"
CHROOT
sed -i \
  -e "s/@LUKS_UUID@/${LUKS_UUID}/g" \
  -e "s/@MAPPER@/${MAPPER}/g" \
  -e "s/@NEWUSER@/${NEWUSER}/g" \
  "$chroot_script"
chmod 700 "$chroot_script"

say "arch-chroot /mnt (timezone/locale EDIT-ME, hostname, user, bootctl, mkinitcpio)"
arch-chroot /mnt /root/.archhypr-chroot.sh
rm -f /mnt/root/.archhypr-chroot.sh

# ---------- (j) next steps --------------------------------------------------

cat <<EOF

==> base system is on $TARGET (LUKS UUID $LUKS_UUID, mapper $MAPPER).

First boot:
  1. reboot  (or: umount -R /mnt && cryptsetup close $MAPPER && reboot)
  2. remove the Arch ISO
  3. boot the USB from the firmware boot menu (systemd-boot on the ESP)
  4. unlock LUKS with the passphrase you just set
  5. log in as ${NEWUSER}  (sudo via wheel)
  6. EDIT-ME: timedatectl set-timezone Region/City
              (see /etc/archhypr-EDIT-ME)

Then install Hyprland + dots from this repo:
  sudo pacman -S --needed git
  git clone <arch-hypr-url> ~/arch-hypr
  cd ~/arch-hypr
  ./install.sh

On this 64GB stick, drop the heavy modules:
  ./install.sh --profile lite
  # equivalent: ./install.sh --without steam,security

EOF
