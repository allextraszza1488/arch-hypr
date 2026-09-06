#!/bin/bash
# -----------------------------------------------------------------------------
# Dropdown terminal on a hidden workspace. Bound to SUPER+S.
# Replaces pyprland's most common use case natively -- pyprland is AUR-only.
# -----------------------------------------------------------------------------
set -euo pipefail

export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" | head -1)"

# is the scratchpad workspace empty? decides spawn-then-show vs just show
empty=$(hyprctl clients -j | jq '[.[] | select(.workspace.name=="special:scratch")] | length == 0')

if [ "$empty" = "true" ]; then
  # lazy first use: spawn kitty straight onto the hidden workspace, silently
  hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("[workspace special:scratch silent] kitty"))'
  # give the window time to map, or the toggle below shows an empty workspace
  sleep 0.15
fi

# show it if hidden, hide it if shown
hyprctl eval 'hl.dispatch(hl.dsp.workspace.toggle_special("scratch"))'
