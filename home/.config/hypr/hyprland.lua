-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("hypr.atmos_layout")
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.workspaces")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.windows")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("hypr.atmos")
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Screenshots from Print Screen, Super+Shift+S, and the capture menu all
-- land in the existing Pictures/Screenshots archive. hl.env is required so
-- Hyprland keybind dispatchers see the variable (hyprctl setenv does not).
hl.env("OMARCHY_SCREENSHOT_DIR", os.getenv("HOME") .. "/Pictures/Screenshots")

-- YouTube recordings are prepared automatically after capture stops.
hl.env("OMARCHY_SCREENRECORD_DIR", os.getenv("HOME") .. "/YouTube/inbox")

-- Keep VA-API video decode on the Intel iGPU that drives this display.
--
-- Omarchy's default.hypr.nvidia sets LIBVA_DRIVER_NAME=nvidia whenever an
-- NVIDIA GPU is present, but on this hybrid laptop the displays are driven by
-- Intel (i915) and every Chromium GPU process composites on /dev/dri/renderD129
-- (Intel). Decoding on the dGPU hands Chromium dmabufs that its Intel EGL stack
-- cannot import (eglCreateImage returns EGL_BAD_PARAMETER), so playback runs
-- normally while every frame composites black.
--
-- This override is deliberate and is loaded after Omarchy's defaults. The
-- NVIDIA GLX/NVD_BACKEND settings above are left alone; only the VA-API driver
-- selection is corrected. NVDEC can still be requested per command with
-- LIBVA_DRIVER_NAME=nvidia.
hl.env("LIBVA_DRIVER_NAME", "iHD")

-- Tile DaVinci Resolve under the Omarchy bar instead of true-fullscreening
-- over it. See hypr/davinci-resolve.lua.
require("hypr.davinci-resolve")
