#!/bin/bash
# -----------------------------------------------------------------------------
# Swaps the active "look" and reloads everything that shows it.
# Bound to SUPER+SHIFT+T.
#
# Reaches: hyprland borders/glow, kitty colours, wallpaper.
# Does NOT reach: waybar, fuzzel, mako, btop -- they keep hardcoded colours,
# so a toggle changes the frame and leaves the bar behind.
# -----------------------------------------------------------------------------
set -euo pipefail

# the two recipes: alpenflage.lua and tigerstripe.lua
LOOKS_DIR=$HOME/.config/hypr/looks
# hyprland.lua dofile()s this on every reload; this script overwrites it
STATE=$HOME/.config/hypr/look-state.lua
# plain text file holding just the current look's name
MARKER=$HOME/.config/hypr/current-look

# no marker yet means first run; assume alpenflage so the first toggle goes to tigerstripe
current=$(cat "$MARKER" 2>/dev/null || echo "alpenflage")

# only two looks, so "the other one" is a simple flip
if [ "$current" = "alpenflage" ]; then
  next="tigerstripe"
else
  next="alpenflage"
fi

# hyprland picks this up on the reload below
cp "$LOOKS_DIR/$next.lua" "$STATE"
echo "$next" > "$MARKER"

export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" | head -1)"
# re-reads hyprland.lua, which re-reads look-state.lua
hyprctl reload

# kitty.conf includes this file; only NEW kitty windows pick it up
cp $HOME/.config/kitty/looks/"$next".conf \
   $HOME/.config/kitty/active-look.conf

# parse the recipe with real Lua rather than grepping Lua syntax with sed
wallpaper=$(lua5.4 -e "io.write(dofile('$LOOKS_DIR/$next.lua').wallpaper)")

# hyprpaper has no reload command, so its config is rewritten and it is restarted
cat > $HOME/.config/hypr/hyprpaper.conf <<EOF2
preload = $wallpaper
wallpaper {
    monitor =
    path = $wallpaper

    fit_mode = cover

}
EOF2

# -----------------------------------------------------------------------------
# Start the NEW hyprpaper BEFORE killing the old one. Kill-then-start left a
# visible gap with no wallpaper daemon at all. Overlapping means there is never
# a moment with zero instances running.
# -----------------------------------------------------------------------------
old_pids=$(pgrep -x hyprpaper || true)
hyprpaper &
new_pid=$!
disown
sleep 0.3
# only the OLD pids, never the one just started
for pid in $old_pids; do
  kill "$pid" 2>/dev/null || true
done

# mako shows this; || true so a missing notification daemon is not fatal
notify-send "Look" "Switched to $next" 2>/dev/null || true
