#!/bin/bash
# -----------------------------------------------------------------------------
# Watches ~/Pictures/Screenshots and copies each new file's PATH to the
# clipboard. Runs forever as the user service scripts/screenshot-watch.service.
# If screenshot paths stop reaching your clipboard, look at that unit, not here.
# -----------------------------------------------------------------------------

# grim writes here; the screenshot binds in hyprland.lua create the directory
DIR="$HOME/Pictures/Screenshots"

# -----------------------------------------------------------------------------
# Find the compositor socket ourselves. systemd starts this unit at LOGIN, which
# is BEFORE Hyprland exists, so the service never inherits WAYLAND_DISPLAY and
# wl-copy silently fails -- screenshots still save, they just never reach the
# clipboard. Re-resolved on demand so restarting the compositor does not strand
# the watcher until the next reboot.
# -----------------------------------------------------------------------------
resolve_wayland() {
    # already pointing at a live socket, nothing to do
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
        return 0
    fi
    for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
        # wayland-N.lock sits beside wayland-N and is not a socket
        case "$sock" in *.lock) continue ;; esac
        if [ -S "$sock" ]; then
            export WAYLAND_DISPLAY="${sock##*/}"
            return 0
        fi
    done
    return 1
}

# last path successfully copied, so the same shot is not copied twice
last=""

while true; do
    # newest png by mtime
    latest=$(ls -t "$DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$latest" ] && [ "$latest" != "$last" ]; then
        # only mark done if the copy WORKED, so a shot taken before the
        # compositor is up gets retried instead of skipped forever
        if resolve_wayland && printf '%s' "$latest" | wl-copy; then
            last="$latest"
        fi
    fi
    # polling, not inotify: simple, and one wakeup a second costs nothing
    sleep 1
done
