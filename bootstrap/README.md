# bootstrap — blank-disk Arch base (before `install.sh`)

Two different scripts, two different machines, two different users.

| | `bootstrap/live-install.sh` | `install.sh` |
| --- | --- | --- |
| When | Blank (or re-used) ~64GB USB, **from the Arch live ISO** | Arch already installed and **already booted** |
| Who | **root** | **you** (refuses uid 0) |
| Disk | Wipes the target whole disk you pass | Refuses any root device other than this machine's `/` |
| Does | GPT + LUKS2 + btrfs `@`/`@home` + pacstrap + systemd-boot | Hyprland stack, dots, GPU, optional steam/security/… |

`install.sh` will not partition a disk and will not install a base system.
`live-install.sh` will not lay down Hyprland. Run them in that order, on
a 64GB stick meant to be a portable 24/7 daily-driver, not live-persistence.

Layout `live-install.sh` writes:

- p1 ~512MiB vfat ESP (unencrypted; firmware requirement)
- p2 rest of the disk, LUKS2, opened as mapper `cryptroot`
- btrfs on the mapper, subvolumes `@` → `/` and `@home` → `/home`
- no swap partition (zram belongs on the installed system)
- bootloader: **systemd-boot**, not GRUB

Hostname is `archhypr`. Timezone/locale are UTC / `en_US.UTF-8` placeholders
marked **EDIT-ME** (`/etc/archhypr-EDIT-ME`).

---

## WARNING — `live-install.sh` wipes a whole disk

`live-install.sh /dev/sdX` runs `sgdisk --zap-all` on that device. A
wrong name (`/dev/sda` instead of `/dev/sdb`, the NVMe that already has
your main OS, the stick you booted the ISO from) **destroys that disk**.

It will:

- refuse to run if you are not root
- refuse a partition (`/dev/sdb1`); pass the whole disk
- refuse a size that is not close to 64GB
- refuse the live-ISO boot disk
- print model / serial / current layout
- refuse to continue unless you type `yes` in full (`y` is not enough)

**Check `lsblk` twice. Then type `yes`.**

---

## How to get this repo into the live environment

The target 64GB stick is the disk being wiped. Do **not** keep the repo
on that stick. Use a second device, or the network.

### A. Arch ISO USB + network (simplest)

1. Flash the official Arch ISO to a **different** USB than the 64GB target.
2. Boot it: firmware boot menu → the ISO stick, UEFI mode.
3. In the live shell, bring the network up (`iwctl` for Wi-Fi, or plug in
   Ethernet — NetworkManager is not the live ISO's default; `iwctl` /
   `dhcpcd` are):

   ```bash
   # Wi-Fi example
   iwctl station wlan0 connect 'SSID'
   ```

4. Fetch the repo, then run the bootstrap against the **64GB** device
   (`lsblk` first):

   ```bash
   pacman -Sy --needed git
   git clone <arch-hypr-git-url> /tmp/arch-hypr
   lsblk
   bash /tmp/arch-hypr/bootstrap/live-install.sh /dev/sdX
   ```

   If the repo is only reachable as a raw file:

   ```bash
   curl -L -o /tmp/live-install.sh <raw-git-url>/bootstrap/live-install.sh
   bash /tmp/live-install.sh /dev/sdX
   ```

   `live-install.sh` is standalone (it does not source `lib/`). The rest
   of the repo is needed only after first boot, when you run `install.sh`.

### B. Repo on a small FAT partition of the *ISO* stick (offline)

Leave the 64GB target empty. On the **installer** USB (the one that
holds the Arch ISO), add a second small FAT partition and copy this
repo onto it before you boot. Then:

```bash
mkdir -p /media/repo
lsblk   # pick the ISO stick's FAT data partition, NOT the 64GB target
mount /dev/sdY2 /media/repo
bash /media/repo/arch-hypr/bootstrap/live-install.sh /dev/sdX
```

`sdY` = ISO stick, `sdX` = 64GB target. Mixing those two names is the
wipe-the-wrong-disk failure mode.

---

## After `live-install.sh`

Reboot, remove the ISO, boot the 64GB stick, unlock LUKS, log in as the
user you created, clone this repo if it is not already there, then:

```bash
cd ~/arch-hypr
./install.sh
```

On a tight 64GB stick use the lite profile (drops `steam` and `security`;
see `lite-profile.sh`):

```bash
./install.sh --profile lite
```

That is the same as `./install.sh --without steam,security`. `--profile`
is a wrapper around the existing `--without` list, not a second module
planner.
