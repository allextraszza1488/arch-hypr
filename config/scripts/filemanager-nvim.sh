#!/bin/bash
# -----------------------------------------------------------------------------
# Launches the standalone nvim file manager (nvim-fm/init.lua).
# Bound to SUPER+F, and also run by ~/.local/share/applications/
# filemanager-nvim.desktop, which mimeapps.list maps to inode/directory --
# which is why opening a folder anywhere on the system lands here.
# -----------------------------------------------------------------------------

# starting directory; init.lua reads this, $1 comes from the .desktop %f
export NVIM_FM_START_DIR="${1:-$HOME}"

# --class so hyprland.lua can match it; -u loads nvim-fm INSTEAD of your normal config
exec kitty --class filemanager -e nvim -u "$HOME/.config/nvim-fm/init.lua"
