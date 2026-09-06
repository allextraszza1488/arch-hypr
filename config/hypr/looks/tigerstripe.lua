-- "tigerstripe" look: dark black/grey scheme. Same shape as alpenflage.lua
-- on purpose -- the toggle script just swaps which of these two files is
-- active, hyprland.lua doesn't care which one it got.
return {
  border_active   = { "rgba(2b2b2bee)", "rgba(6e6e6eee)" },
  border_inactive = "rgba(0d0d0dee)",
  glow_active     = "rgba(8a8a8aa6)",
  glow_inactive   = "rgba(2b2b2b33)",
  wallpaper       = os.getenv("HOME") .. "/Pictures/tigerstripe-wallpaper.webp",
}
