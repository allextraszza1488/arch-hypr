#!/bin/bash
# -----------------------------------------------------------------------------
# Category picker over the three reference sheets. Bound to SUPER+SHIFT+A.
# One level up from keybind-cheatsheet.sh, which jumps straight to keybinds.
# -----------------------------------------------------------------------------
set -euo pipefail

export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" | head -1)"

# all three sheets live here; hand-maintained plain text, one entry per line
DIR="$HOME/.config/reference"

# first menu: which sheet
category=$(printf 'Keybinds\nLinux commands\nVim cheatsheet' | fuzzel --dmenu --prompt "shortcuts> ")

# second menu: filter within the chosen sheet, read-only
case "$category" in
  Keybinds)         fuzzel --dmenu --prompt "keybinds> "       < "$DIR/keybinds.txt"        >/dev/null ;;
  "Linux commands") fuzzel --dmenu --prompt "commands> "       < "$DIR/linux-commands.txt"  >/dev/null ;;
  "Vim cheatsheet") fuzzel --dmenu --prompt "vim> "             < "$DIR/vim-cheatsheet.txt"  >/dev/null ;;
  *) exit 0 ;;
esac
