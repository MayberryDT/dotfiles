-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

hl.unbind("SUPER + CTRL + X")
hl.unbind("SUPER + SHIFT + CTRL + A")
hl.unbind("SUPER + SPACE")
hl.unbind("SUPER + SHIFT + S")

-- Windows Snipping Tool muscle memory: select a region, copy to clipboard,
-- and save into ~/Pictures/Screenshots. Print Screen uses the same folder.
-- Replaces the stock Google Maps webapp bind.
o.bind("SUPER + SHIFT + S", "Snipping tool", "omarchy-capture-screenshot region")

-- Mint-style overlay key: a tap of either Super key toggles the Omarchy menu,
-- but using Super as part of another keyboard chord cancels the tap. Hyprland's
-- keyboard event reports XKB keycodes (Left/Right Super = 133/134).
-- Workspace switcher HUD stays up while Ctrl+Alt or Super+Tab is held, then
-- hides on release. XKB: Ctrl 37/105, Alt 64/108, Tab 23.
local super_keys = { [133] = true, [134] = true }
local ctrl_keys = { [37] = true, [105] = true }
local alt_keys = { [64] = true, [108] = true }
local tab_key = 23
local super_down = {}
local ctrl_down = {}
local alt_down = {}
local super_tap_armed = false
local ctrl_alt_switcher_held = false
local super_switcher_held = false

local function workspace_switcher_hold()
  hl.exec_cmd("omarchy-shell -q io.zet.workspace-switcher hold")
end

local function workspace_switcher_hide()
  hl.exec_cmd("omarchy-shell -q io.zet.workspace-switcher hide")
end

hl.on("input.keyboard.key", function(keycode, _, state)
  local pressed = (state == 1 or state == 2)
  local released = (state == 0)

  if ctrl_keys[keycode] then
    if pressed then
      ctrl_down[keycode] = true
    elseif released then
      ctrl_down[keycode] = nil
    end
  elseif alt_keys[keycode] then
    if pressed then
      alt_down[keycode] = true
    elseif released then
      alt_down[keycode] = nil
    end
  end

  local ctrl_alt_down = next(ctrl_down) ~= nil and next(alt_down) ~= nil
  if ctrl_alt_down and not ctrl_alt_switcher_held then
    ctrl_alt_switcher_held = true
    workspace_switcher_hold()
  elseif ctrl_alt_switcher_held and not ctrl_alt_down then
    ctrl_alt_switcher_held = false
    workspace_switcher_hide()
  end

  if super_keys[keycode] then
    if state == 1 then
      if next(super_down) == nil then
        super_tap_armed = true
      end
      super_down[keycode] = true
    elseif state == 0 then
      super_down[keycode] = nil
      if next(super_down) == nil then
        if super_tap_armed then
          hl.exec_cmd("omarchy-menu toggle")
        end
        if super_switcher_held then
          super_switcher_held = false
          workspace_switcher_hide()
        end
        super_tap_armed = false
      end
    end
  elseif pressed and next(super_down) ~= nil then
    super_tap_armed = false
    if keycode == tab_key and not super_switcher_held then
      super_switcher_held = true
      workspace_switcher_hold()
    end
  end
end)

o.bind("CTRL + SPACE", "Toggle dictation", "voxtype record toggle")
o.bind("INSERT", "Reinsert last dictation", "/home/tyler/.local/bin/voxtype-history paste-last")
o.bind("SUPER + SHIFT + V", "Paste last dictation", "/home/tyler/.local/bin/voxtype-history paste-last")
o.bind("SUPER + ALT + V", "Dictation history", "/home/tyler/.local/bin/voxtype-history pick")
o.bind("SUPER + SHIFT + CTRL + A", "Zet", "/home/tyler/.local/bin/hermes-desktop-launch")

-- Leave Shift+Tab available to applications.
hl.unbind("SHIFT + TAB")

-- Omamin minimize flow: park the focused window, open the workspace-aware
-- minimized-window panel, or restore the most recently minimized window.
hl.unbind("SUPER + M")
hl.unbind("SUPER + SHIFT + M")
hl.unbind("SUPER + ALT + M")
o.bind("SUPER + M", "Omamin: minimize window or open list", "/home/tyler/.local/bin/zet-omamin-super-m")
o.bind("SUPER + SHIFT + M", "Omamin: minimized windows", "omarchy-shell -q shell toggle io.github.nousd.omamin")
o.bind("SUPER + ALT + M", "Omamin: restore last minimized", "omarchy-shell -q omamin restoreLast")

-- Mint-style workspace flow: adjacent numbered workspaces with the window
-- following when Shift is held. The helper also plays a subtle direction cue.
-- Preserve Omarchy's occupied-workspace cycle on Super+Tab while adding the
-- same sound. Shift moves the focused window to the next occupied workspace
-- and follows it, analogous to Ctrl+Alt+Shift+Arrow's move-and-follow flow.
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Next occupied workspace", "/home/tyler/.local/bin/zet-workspace-flow cycle")
o.bind("SUPER + SHIFT + TAB", "Move window to next occupied workspace", "/home/tyler/.local/bin/zet-workspace-flow cycle move")
-- Replace next-monitor focus with the stock former-workspace action.
hl.unbind("CTRL + ALT + TAB")
o.bind("CTRL + ALT + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))
-- Select numbered workspaces while holding the workspace overview chord.
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  hl.unbind("SUPER + " .. key)
  o.bind("CTRL + ALT + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
end
o.bind("CTRL + ALT + LEFT", "Previous workspace", "/home/tyler/.local/bin/zet-workspace-flow left")
o.bind("CTRL + ALT + RIGHT", "Next workspace", "/home/tyler/.local/bin/zet-workspace-flow right")
o.bind("CTRL + ALT + SHIFT + LEFT", "Move window to previous workspace", "/home/tyler/.local/bin/zet-workspace-flow left move")
o.bind("CTRL + ALT + SHIFT + RIGHT", "Move window to next workspace", "/home/tyler/.local/bin/zet-workspace-flow right move")

-- Note: SUPER+CTRL+O was previously bound to Toggle menu (Super tap still
-- opens the Omarchy menu). Replaced with the bar to-do list.
hl.unbind("SUPER + CTRL + O")
o.bind("SUPER + CTRL + O", "To-do list", "omarchy-shell -q io.zet.todo-list toggle")
o.bind("SUPER + CTRL + X", "Post to X", "/home/tyler/.local/bin/zet-x-compose")
o.bind("SUPER + ALT + X", "HDMI views", "/home/tyler/.local/bin/zet-hdmi-view")

-- Omarchy Find file search overlay. Plugin default is Alt+Space (Spotlight-style).
-- Super+Space stays unbound so Super-tap can still open the Omarchy menu.
o.bind("ALT + SPACE", "Find files & folders", "omarchy-shell -q shell toggle jesseburlamaque.omarchy-find '{}'")


-- strata-installer: file-manager start
hl.unbind("SUPER + SHIFT + F")
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = "/home/tyler/.local/bin/strata" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
  "uwsm-app -- /home/tyler/.local/bin/strata \"$(omarchy-cmd-terminal-cwd)\"")
-- strata-installer: file-manager end
