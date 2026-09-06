# lite profile — sourced by install.sh --profile lite
# Space-tight 64GB USB. Do not execute; source only.
#
# install.sh does not have a module planner beyond ALL_MODULES plus
# --with / --without. Exclusions live in the WITHOUT array (canonical
# names: 00-preflight … 90-steam). This file appends to that same array.

WITHOUT+=(
  80-security
  90-steam
)

# There is no kernel module and no linux+linux-lts dual-kernel default
# in install.sh. linux-lts is only added by 50-snapshots when the
# bootloader is GRUB. Opt out so that path stays on `linux`.
SKIP_LINUX_LTS=1
