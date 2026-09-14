-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Laptop stays at origin. HDMI is physically to the left, so the cursor
-- leaves the laptop on the left edge.
hl.monitor({
  output = "eDP-2",
  mode = "preferred",
  position = "0x0",
  scale = omarchy_monitor_scale,
})
-- CPO Ingnok is physically rotated 90° clockwise (portrait).
-- After transform the logical size is 1080x1920, so it sits at -1080x0
-- with the extra height hanging below the laptop.
hl.monitor({
  output = "HDMI-A-1",
  mode = "preferred",
  position = "-1080x0",
  scale = omarchy_monitor_scale,
  transform = 1,
})

-- Unknown plugs still land automatically.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
