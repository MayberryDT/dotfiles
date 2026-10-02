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
    layout = "dwindle",
  })
end

-- What HDMI-A-1 shows changes only through zet-hdmi-view (Super+Alt+X), which
-- calls zet_hdmi_set_view() before it switches. Anything else that lands
-- another workspace on HDMI is put back to the chosen view at once.
local hdmi_views = { hdmi = true, ["hdmi-x"] = true, ["hdmi-open"] = true }
local hdmi_view = nil

-- On a config reload, keep whatever view HDMI already shows.
do
  local ok, monitor = pcall(hl.get_monitor, "HDMI-A-1")
  local active = ok and monitor and monitor.active_workspace
  if active and hdmi_views[active.name] then hdmi_view = active.name end
end

function zet_hdmi_set_view(name)
  if hdmi_views[name] then hdmi_view = name end
end

hl.on("workspace.active", function(workspace)
  local monitor = workspace and workspace.monitor
  if not monitor or monitor.name ~= "HDMI-A-1" or workspace.special then return end
  if hdmi_view == nil then hdmi_view = hdmi_views[workspace.name] and workspace.name or "hdmi" end
  if workspace.name ~= hdmi_view then
    -- Put it back once the dispatch that moved it has finished: a revert
    -- dispatched from inside that dispatch was overwritten by it.
    hl.timer(function()
      local ok, hdmi = pcall(hl.get_monitor, "HDMI-A-1")
      local active = ok and hdmi and hdmi.active_workspace
      if active and active.name ~= hdmi_view then
        hl.dispatch(hl.dsp.focus({ workspace = "name:" .. hdmi_view }))
      end
    end, { timeout = 1, type = "oneshot" })
  end
end)
