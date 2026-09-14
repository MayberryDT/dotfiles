-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- Smooth horizontal workspace travel. Omarchy disables workspace animation by
-- default; this restores the flow Tyler liked on Mint without changing window
-- animations or monitor scaling.
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Super-menu launches should stay on the current workspace. Omarchy defaults
-- this to true, so activating an existing Codex/Electron window would follow
-- it onto another workspace. New mapped windows still receive focus.
hl.config({
  misc = {
    focus_on_activate = false,
  },
  cursor = {
    -- Avoid the Hyprland/Aquamarine hardware-cursor black-square artifact on
    -- this Intel/NVIDIA multi-GPU setup, especially on the rotated HDMI output
    -- and when Chromium hides the pointer over fullscreen video.
    no_hardware_cursors = 1,
  },
})
