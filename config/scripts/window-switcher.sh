#!/bin/bash
# -----------------------------------------------------------------------------
# Alt-tab replacement: a fuzzel list of open windows, keyboard only.
# Bound to SUPER+Tab in hyprland.lua.
# -----------------------------------------------------------------------------
set -euo pipefail

# hyprctl needs this and a systemd/user service never inherits it
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" | head -1)"

# -----------------------------------------------------------------------------
# Filter ONCE, then use that same filtered array for both the menu and the
# lookup. The previous version numbered a filtered list but looked the address
# up in the UNFILTERED one, so any unmapped window shifted every index and you
# focused the wrong window -- silently, with no error.
# -----------------------------------------------------------------------------
mapped=$(hyprctl clients -j | jq '[.[] | select(.mapped==true)]')

# numbered menu lines, built from the filtered array
list=$(echo "$mapped" | jq -r 'to_entries[] | "\(.key+1): \(.value.class) — \(.value.title)"')

# nothing open, nothing to switch to
[ -z "$list" ] && exit 0

# fuzzel returns the whole chosen line
chosen=$(echo "$list" | fuzzel --dmenu --prompt "window> ")

# escaped out of the menu
[ -z "$chosen" ] && exit 0

# pull the leading number back off the chosen line
idx=$(echo "$chosen" | grep -oE '^[0-9]+')

# no leading number means the line was not one of ours
[ -z "$idx" ] && exit 0

# same array the menu came from, so the index still means what it meant
addr=$(echo "$mapped" | jq -r ".[$((idx-1))].address")

# window vanished between listing and choosing
{ [ -z "$addr" ] || [ "$addr" = "null" ]; } && exit 0

# dispatchers with arguments must go through eval; hyprctl dispatch parses as Lua
hyprctl eval "hl.dispatch(hl.dsp.focus({window = \"address:$addr\"}))"
