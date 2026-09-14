-- Hermes Desktop identity. The gateway-window-title plugin sets
-- document.title after the window maps, so workspace stickiness is handled
-- by ~/.local/bin/zet-hermes-gateway-windows rather than a workspace= rule.
o.window({ class = "^Hermes$", title = "^Hermes · Veelox$" }, { tag = "+hermes-veelox" })
o.window({ class = "^Hermes$", title = "^Hermes · Halla$" }, { tag = "+hermes-halla" })

-- Super+Ctrl+X: X compose webapp, sized like the in-app modal.
o.window("brave-x.com__compose_post-Default", { float = true })
o.window("brave-x.com__compose_post-Default", { center = true })
o.window("brave-x.com__compose_post-Default", { size = { 600, 640 } })

-- Permanent X PWA on the HDMI portrait workspace. silent so a launch from
-- the laptop does not steal focus. Distinct class from the compose float.
o.window("brave-x.com__home-Default", {
  workspace = "hdmi-x silent",
  monitor = "HDMI-A-1",
  fullscreen = true,
})

-- Infomarchy is a real window dedicated to the HDMI status workspace.
-- workspace/monitor/fullscreen are static (apply on map only), so also
-- yank the window back if it is later moved onto the laptop.
o.window({ class = "^org\\.quickshell$", title = "^Infomarchy HDMI Status$" }, {
  workspace = "hdmi silent",
  monitor = "HDMI-A-1",
  fullscreen = true,
  no_initial_focus = true,
})

local hdmi_status_pinning = false

local function is_hdmi_status(w)
  return w ~= nil
    and w.class == "org.quickshell"
    and (w.title == "Infomarchy HDMI Status" or w.initial_title == "Infomarchy HDMI Status")
end

local function hdmi_connected()
  local mon = hl.get_monitor("HDMI-A-1")
  return mon ~= nil
end

local function pin_hdmi_status(w)
  if hdmi_status_pinning or not is_hdmi_status(w) or not hdmi_connected() then
    return
  end
  local ws = w.workspace
  local mon = w.monitor
  if ws ~= nil and ws.name == "hdmi" and mon ~= nil and mon.name == "HDMI-A-1" and w.fullscreen ~= 0 then
    return
  end
  hdmi_status_pinning = true
  hl.dispatch(hl.dsp.window.move({
    workspace = "name:hdmi",
    follow = false,
    window = w,
  }))
  if w.fullscreen == 0 then
    hl.dispatch(hl.dsp.window.fullscreen({
      mode = "fullscreen",
      action = "set",
      window = w,
    }))
  end
  hdmi_status_pinning = false
end

local function pin_all_hdmi_status()
  for _, w in ipairs(hl.get_windows()) do
    pin_hdmi_status(w)
  end
end

hl.on("window.open", pin_hdmi_status)
hl.on("window.title", pin_hdmi_status)
hl.on("window.move_to_workspace", function(w, _)
  pin_hdmi_status(w)
end)
hl.on("monitor.added", function(mon)
  if mon ~= nil and mon.name == "HDMI-A-1" then
    pin_all_hdmi_status()
  end
end)
hl.on("config.reloaded", pin_all_hdmi_status)
