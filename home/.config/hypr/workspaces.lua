-- One workspace spans both monitors: workspace N is Hyprland workspace N on the
-- left monitor and N+10 on the right (see ~/.local/bin/zet-workspace-flow).
-- These rules only give each monitor its starting workspace; the flow script
-- decides by position which monitor shows which half.
for workspace = 1, 10 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = "eDP-2",
    default = (workspace == 1),
    layout = "dwindle",
  })
  hl.workspace_rule({
    workspace = tostring(workspace + 10),
    monitor = "HDMI-A-1",
    default = (workspace == 1),
    layout = "dwindle",
  })
end

-- A monitor came or went (including the lid in clamshell): show the current
-- workspace on every monitor, and with one left fold the right halves into it.
for _, event in ipairs({ "monitor.added", "monitor.removed" }) do
  hl.on(event, function()
    hl.exec_cmd("/home/tyler/.local/bin/zet-workspace-flow sync")
  end)
end
