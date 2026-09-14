-- HDMI is an extra visible workspace set, same idea as Omamin's hidden
-- special:minimized — outside the numbered 1-10 laptop flow.
-- Do not use a special: workspace here; those are overlays, not a monitor home.
--
-- Three persistent HDMI-only views, cycled by zet-hdmi-view:
--   hdmi      status board
--   hdmi-x    full-screen X PWA
--   hdmi-open blank workspace that stays on this monitor

for _, name in ipairs({ "hdmi", "hdmi-x", "hdmi-open" }) do
  hl.workspace_rule({
    workspace = "name:" .. name,
    monitor = "HDMI-A-1",
    default = (name == "hdmi"),
    persistent = true,
  })
end

for workspace = 1, 10 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = "eDP-2",
    default = (workspace == 1),
  })
end
