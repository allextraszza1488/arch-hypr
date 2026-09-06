-- =============================================================================
-- hyprland.lua -- the one file that knows about the others
-- Hyprland >= 0.55 configures in Lua. hyprland.conf is dead. Reload: hyprctl reload
-- =============================================================================


-- -----------------------------------------------------------------------------
-- NAMES -- every program the binds below refer to, changed in one place
-- -----------------------------------------------------------------------------

-- window-management modifier; SUPER only, so nothing can collide inside nvim
local mod       = "SUPER"
-- terminal, opened by SUPER+Return and wrapped around btop and yazi
local terminal  = "kitty"
-- browser, opened by SUPER+B
local browser   = "firefox"
-- app launcher and the dmenu backend every menu script pipes into
local launcher  = "fuzzel"
-- terminal file manager, opened by SUPER+N (not the nvim one, that is SUPER+F)
local files     = "yazi"


-- -----------------------------------------------------------------------------
-- PATHS -- built from $HOME so this file works under any username
-- -----------------------------------------------------------------------------

-- real Lua, so os.getenv works at load time; a literal /home/name breaks the laptop
local home    = os.getenv("HOME")
-- root of everything this config touches
local conf    = home .. "/.config"
-- the REAL scripts directory, not the ~/.local/bin symlinks that once went dangling
local scripts = conf .. "/scripts"


-- -----------------------------------------------------------------------------
-- LOOK -- colours, re-read from disk on every reload
-- -----------------------------------------------------------------------------

-- toggle-look.sh overwrites this file with one of hypr/looks/*.lua; dofile re-reads it
local look = dofile(conf .. "/hypr/look-state.lua")


-- -----------------------------------------------------------------------------
-- AUTOSTART -- the ONE start block; a second one runs IN ADDITION, not instead
-- -----------------------------------------------------------------------------

hl.on("hyprland.start", function()
    -- wallpaper daemon; reads hypr/hyprpaper.conf, also written by toggle-look.sh
    hl.exec_cmd("hyprpaper")
    -- notification daemon; self-guards against a second instance, which hid a bug once
    hl.exec_cmd("mako")
    -- status bar; has NO single-instance guard, so a duplicate start stacks two bars
    hl.exec_cmd("waybar")
end)


-- -----------------------------------------------------------------------------
-- APPEARANCE -- gaps, borders, blur, glow, tiling layout
-- -----------------------------------------------------------------------------

hl.config({
  general = {
    -- gap between tiled windows
    gaps_in = 4,
    -- gap between windows and the screen edge
    gaps_out = 8,
    -- thick border, because the look is carried almost entirely by border colour
    border_size = 7,
    -- dwindle: every new window splits the focused one in half
    layout = "dwindle",
    -- drag the border itself to resize, no modifier needed
    resize_on_border = true,
    col = {
      -- two-stop gradient at 45 degrees, colours from the active look
      active_border   = { colors = look.border_active, angle = 45 },
      -- flat colour for everything not focused
      inactive_border = look.border_inactive,
    },
  },
  decoration = {
    -- corner radius on every window
    rounding = 8,
    -- focused window very slightly transparent
    active_opacity = 0.98,
    -- unfocused windows noticeably transparent, so focus is obvious at a glance
    inactive_opacity = 0.85,
    -- background blur behind transparent windows
    blur   = { enabled = true, size = 6, passes = 2 },
    -- drop shadow; colour is ARGB, 0x55 alpha
    shadow = { enabled = true, range = 16, render_power = 3, color = 0x55000000 },
    glow = {
      -- coloured halo around the focused window, on top of the border
      enabled        = true,
      -- glow colour for the focused window, from the active look
      color          = look.glow_active,
      -- dimmer glow for everything else
      color_inactive = look.glow_inactive,
      -- how far the glow spreads in pixels
      range          = 20,
      -- falloff curve; higher is a tighter, sharper glow
      render_power   = 3,
    },
  },
  dwindle = {
    -- keep the split direction when a window closes, so the layout stops reshuffling
    preserve_split = true,
  },
  input = {
    kb_layout = "us",
    -- 0 = focus follows clicks only; move focus with SUPER+hjkl, never the mouse
    follow_mouse = 0,
  },
  misc = {
    -- no Hyprland logo on an empty workspace
    disable_hyprland_logo = true,
    -- no stock wallpaper either; hyprpaper owns the background
    force_default_wallpaper = 0,
  },
  cursor = {
    -- hardware cursor planes ON; false here would cost a little GPU for no gain
    no_hardware_cursors = false,
  },
  animations = { enabled = true },-- //kindawanna off cuz idc bout that but aight keep it
})


-- -----------------------------------------------------------------------------
-- MONITOR -- optional host overlay pins a panel; without it Hyprland picks
-- -----------------------------------------------------------------------------

-- Host overlay (monitor pin, etc). Absent on a laptop / unknown host --
-- pcall so a missing file does not throw at parse time and the compositor
-- still starts, with whatever mode Hyprland auto-selects.
pcall(dofile, conf .. "/hypr/host.lua")


-- -----------------------------------------------------------------------------
-- ANIMATIONS -- two curves, reused by every animated thing below
-- -----------------------------------------------------------------------------

-- slow-out curve; the general-purpose one
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
-- snappier curve, used only for fades
hl.curve("quick",        { type = "bezier", points = { {0.15, 0}, {0.10, 1} } })

-- windows pop in from 85% size rather than sliding
hl.animation({ leaf = "windows",    enabled = true, speed = 4.5, bezier = "easeOutQuint", style = "popin 85%" })
-- border gradient animates when focus moves
hl.animation({ leaf = "border",     enabled = true, speed = 5.4, bezier = "easeOutQuint" })
-- opacity fades, fastest of the four so focus changes feel immediate
hl.animation({ leaf = "fade",       enabled = true, speed = 3.0, bezier = "quick" })
-- workspaces slide sideways; slowest, because it is the biggest visual move
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "slide" })


-- -----------------------------------------------------------------------------
-- GPU -- NVIDIA vars, but only on a machine that actually has one
-- -----------------------------------------------------------------------------

-- detect rather than hardcode: this config is shared with an AMD laptop
local function has_nvidia()
  -- count VGA controllers whose description mentions nvidia
  local pipe = io.popen("lspci 2>/dev/null | grep -ci 'vga.*nvidia'")
  -- popen failed entirely, so assume no NVIDIA rather than crash the config
  if not pipe then return false end
  local count = tonumber(pipe:read("*a")) or 0
  pipe:close()
  return count > 0
end

if has_nvidia() then
  -- on an AMD box this BREAKS VA-API decode rather than being ignored
  hl.env("LIBVA_DRIVER_NAME", "nvidia")
  -- pick NVIDIA's GLX vendor library instead of mesa's
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
end

-- cursor size for apps that read it from the environment rather than the compositor
hl.env("XCURSOR_SIZE", "24")

-- fuzzel wraps Terminal=true .desktop entries as "$TERMINAL -e"; unset it fails silently
hl.env("TERMINAL", "kitty")


-- -----------------------------------------------------------------------------
-- WINDOW RULES -- float genuine dialogs, tile everything else
-- -----------------------------------------------------------------------------

hl.window_rule({
  name  = "float-dialogs",
  -- the three system dialogs that are unusable when tiled
  match = { class = "^(pavucontrol|nm-connection-editor|blueman-manager)$" },
  float = true,
})

hl.window_rule({
  name  = "suppress-maximize",
  -- every window: ignore apps that maximise themselves on startup
  match = { class = ".*" },
  suppress_event = "maximize",
})


-- -----------------------------------------------------------------------------
-- APPS -- launching things
-- Changing a bind here means editing reference/keybinds.txt too. Nothing checks.
-- -----------------------------------------------------------------------------

-- SUPER+Q closes; Hyprland's default is "open terminal", the opposite of GNOME
hl.bind(mod .. " + Q", hl.dsp.window.close())
-- new terminal
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
-- browser
hl.bind(mod .. " + B", hl.dsp.exec_cmd(browser))
-- app launcher
hl.bind(mod .. " + D", hl.dsp.exec_cmd(launcher))
-- yazi in a terminal window
hl.bind(mod .. " + N", hl.dsp.exec_cmd(terminal .. " -e " .. files))
-- nvim-based file manager; the .desktop entry launches this same script for folders
hl.bind(mod .. " + F", hl.dsp.exec_cmd(scripts .. "/filemanager-nvim.sh"))
-- system monitor, on the Windows muscle-memory chord
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd(terminal .. " -e btop"))
-- picker over keybinds / linux commands / vim cheatsheet
hl.bind(mod .. " + SHIFT + A", hl.dsp.exec_cmd(scripts .. "/shortcuts-hub.sh"))

-- imv, spawned by nvim-fm/init.lua when you press Enter on an image
hl.window_rule({
  name  = "image-preview-float",
  match = { class = "^(imv)$" },
  float = true,
  -- muParser EXPRESSION, not a percentage; "%" is modulo and fails silently at apply time
  size  = { "monitor_w*0.7", "monitor_h*0.8" },
})

-- the editor nvim-fm opens on Enter gets no rule at all: it tiles, like everything else


-- -----------------------------------------------------------------------------
-- FOCUS / MOVE / RESIZE -- arrows and hjkl driven from one table
-- -----------------------------------------------------------------------------

-- pixels per resize step
local step = 40

-- one row per direction: { arrow key, vim key, direction, resize dx, resize dy }
local dirs = {
  { "left",  "H", "left",  -step, 0     },
  { "down",  "J", "down",  0,      step },
  { "up",    "K", "up",    0,     -step },
  { "right", "L", "right",  step,  0    },
}

-- 4 rows x 2 key names x 3 actions = 24 binds, and arrows can never drift from hjkl
for _, d in ipairs(dirs) do
  local arrow, vim, dir, rx, ry = d[1], d[2], d[3], d[4], d[5]
  for _, key in ipairs({ arrow, vim }) do
    -- SUPER + dir: move focus
    hl.bind(mod .. " + " .. key,
            hl.dsp.focus({ direction = dir }))
    -- SUPER + SHIFT + dir: move the window, swapping it with its neighbour
    hl.bind(mod .. " + SHIFT + " .. key,
            hl.dsp.window.move({ direction = dir }))
    -- SUPER + CTRL + dir: resize, repeating while held
    hl.bind(mod .. " + CTRL + " .. key,
            hl.dsp.window.resize({ x = rx, y = ry, relative = true }),
            { repeating = true })
  end
end


-- -----------------------------------------------------------------------------
-- LAYOUT -- per-window state
-- -----------------------------------------------------------------------------

-- float / unfloat the focused window
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- maximize; on M and not F, because F is the file manager
hl.bind(mod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }))
-- true fullscreen, no bar, no gaps
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
-- pseudo-tile: keeps the window's own size inside its tile
hl.bind(mod .. " + P", hl.dsp.window.pseudo())
-- flip the split direction of the current dwindle node
hl.bind(mod .. " + E", hl.dsp.layout("togglesplit"))   -- dwindle only
-- centre a floating window
hl.bind(mod .. " + C", hl.dsp.window.center())

-- alt-tab, keyboard-only: a fuzzel list of open windows
hl.bind(mod .. " + Tab", hl.dsp.exec_cmd(scripts .. "/window-switcher.sh"))

-- SUPER + left mouse drags a window
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
-- SUPER + right mouse resizes it
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })


-- -----------------------------------------------------------------------------
-- RESIZE SUBMAP -- a mode, so you can let go of the modifiers
-- -----------------------------------------------------------------------------

-- resize one way and move the same amount the other, which drags the opposite edge
local function edge(rx, ry, mx, my)
  return function()
    hl.dispatch(hl.dsp.window.resize({ x = rx, y = ry, relative = true }))
    hl.dispatch(hl.dsp.window.move({ x = mx, y = my, relative = true }))
  end
end

-- enter resize mode
hl.bind(mod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
  -- same dirs table as above, so the two can never disagree
  for _, d in ipairs(dirs) do
    local arrow, vim, _, rx, ry = d[1], d[2], d[3], d[4], d[5]
    for _, key in ipairs({ arrow, vim }) do
      -- bare key drags the right or bottom edge
      hl.bind(key,
              hl.dsp.window.resize({ x = rx, y = ry, relative = true }),
              { repeating = true })
      -- SHIFT + key drags the left or top edge instead
      hl.bind("SHIFT + " .. key, edge(-rx, -ry, rx, ry), { repeating = true })
    end
  end
  -- escape leaves the mode
  hl.bind("escape", hl.dsp.submap("reset"))
  -- so does Return, because escape is not always the reflex
  hl.bind("Return", hl.dsp.submap("reset"))
end)


-- -----------------------------------------------------------------------------
-- WORKSPACES -- there is deliberately NO minimize; it hid windows with no trace
-- Stranded on a special workspace? hyprctl clients -j | grep -B5 special
-- -----------------------------------------------------------------------------

for i = 1, 9 do
  -- SUPER + number: go to that workspace
  hl.bind(mod .. " + " .. i,           hl.dsp.focus({ workspace = i }))
  -- SUPER + SHIFT + number: send the window there
  hl.bind(mod .. " + SHIFT + " .. i,   hl.dsp.window.move({ workspace = i }))
end

-- previous existing workspace; "e-1" skips empty ones
hl.bind(mod .. " + bracketleft",  hl.dsp.focus({ workspace = "e-1" }))
-- next existing workspace
hl.bind(mod .. " + bracketright", hl.dsp.focus({ workspace = "e+1" }))
-- scroll wheel does the same as the brackets
hl.bind(mod .. " + mouse_up",     hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse_down",   hl.dsp.focus({ workspace = "e+1" }))


-- -----------------------------------------------------------------------------
-- SCRATCHPAD -- a dropdown terminal on its own hidden workspace
-- -----------------------------------------------------------------------------

-- toggle it; the script spawns kitty into it on first use
hl.bind(mod .. " + S",        hl.dsp.exec_cmd(scripts .. "/scratchpad-term.sh"))
-- throw the focused window into the scratchpad instead
hl.bind(mod .. " + CTRL + S", hl.dsp.window.move({ workspace = "special:scratch" }))


-- -----------------------------------------------------------------------------
-- MENUS -- fuzzel lists, same idiom as the launcher
-- -----------------------------------------------------------------------------

-- logout / reboot / shutdown; suspend is absent until fix-suspend-hang.sh is run
hl.bind(mod .. " + SHIFT + P",     hl.dsp.exec_cmd(scripts .. "/power-menu.sh"))
-- keybind cheatsheet; reads reference/keybinds.txt, which is maintained BY HAND
hl.bind(mod .. " + SHIFT + slash", hl.dsp.exec_cmd(scripts .. "/keybind-cheatsheet.sh"))


-- -----------------------------------------------------------------------------
-- AUDIO -- media keys; no desktop environment means nothing else handles them
-- -----------------------------------------------------------------------------

-- volume up; -l 1 caps at 100% so it cannot be pushed into distortion
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
-- volume down
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
-- mute toggle; locked = true means these work on the lock screen too
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })


-- -----------------------------------------------------------------------------
-- SCREENSHOT -- saves to ~/Pictures/Screenshots, watched by screenshot-watch.sh
-- That watcher copies each new file's PATH to the clipboard via wl-copy
-- -----------------------------------------------------------------------------

-- slurp picks a region, grim captures it, date names it
local region_screenshot = hl.dsp.exec_cmd(
  "bash -c 'mkdir -p ~/Pictures/Screenshots && " ..
  "grim -g \"$(slurp)\" ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png'")

-- region shot, matching Win+Shift+S
hl.bind(mod .. " + SHIFT + S",     region_screenshot)
-- same action, for keyboards without a Super key
hl.bind(mod .. " + SHIFT + Print", region_screenshot)
-- whole screen, no selection
hl.bind("Print", hl.dsp.exec_cmd(
  "bash -c 'mkdir -p ~/Pictures/Screenshots && " ..
  "grim ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png'"))


-- -----------------------------------------------------------------------------
-- SELF-CONTROL -- reload this file, swap the look
-- A look reaches hypr + kitty + wallpaper only; waybar and fuzzel keep their own
-- -----------------------------------------------------------------------------

-- re-read this file without restarting the session
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))
-- swap alpenflage <-> tigerstripe
hl.bind(mod .. " + SHIFT + T", hl.dsp.exec_cmd(scripts .. "/toggle-look.sh"))
