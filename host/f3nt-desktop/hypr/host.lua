-- host/f3nt-desktop overlay. Loaded via pcall(dofile) from hyprland.lua.
-- Pin the panel; without this Hyprland picks the slowest mode it can.
-- Live cable is currently on the iGPU as DP-4 @ ~60Hz; this pin is what
-- the shared config used to hardcode (DP-1 2560x1440@120).
hl.monitor({
  output = "DP-1",
  -- 120 not the panel's 199.99: measured 26.2W vs 29.8W idle, 60Hz saved nothing more
  mode = "2560x1440@120.00",
  position = "auto",
  scale = "1",
})
