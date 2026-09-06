#!/bin/bash
# -----------------------------------------------------------------------------
# Searchable keybind list. Bound to SUPER+SHIFT+/.
# Reads reference/keybinds.txt, which is maintained BY HAND and drifts from
# hyprland.lua whenever a bind changes. Nothing checks that they agree.
# -----------------------------------------------------------------------------
set -euo pipefail

# hyprctl and fuzzel need this; a service started at login never inherits it
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" | head -1)"

# dmenu mode turns fuzzel into a filter over stdin; output discarded, this is read-only
fuzzel --dmenu --prompt "keybinds> " < "$HOME/.config/reference/keybinds.txt" >/dev/null
