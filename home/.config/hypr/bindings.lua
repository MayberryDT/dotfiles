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
-- Closing the lid must not lock this unattended agent workstation. Keep the
-- stock monitor reconciliation so clamshell/display state still follows the
-- physical lid switch without making the graphical session inaccessible.
hl.unbind("switch:on:Lid Switch")
o.bind("switch:on:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell", { locked = true })
-- Keep every workspace on the standard tiled layout. The stock Super+L
-- toggle can strand an existing workspace in scrolling mode even after it
-- saves "dwindle" for the next session.
hl.unbind("SUPER + L")

-- Windows Snipping Tool muscle memory: select a region, copy to clipboard,
-- and save into ~/Pictures/Screenshots. Print Screen uses the same folder.
-- Replaces the stock Google Maps webapp bind.
o.bind("SUPER + SHIFT + S", "Snipping tool", "omarchy-capture-screenshot region")

-- Restore stock Omarchy menu on Super+Space. Super-tap does not open the menu.
o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle")

-- Workspace switcher HUD (io.zet.workspace-switcher) follows Super: holding
-- Super shows it after a short pause, so a quick Super+key shortcut does not
-- flash it, and Super+Left/Right/Tab show it at once. Letting go of Super
-- hides it. Any other key pressed with Super is a shortcut and takes it down;
-- moving the pointer before the pause ends (Super+drag) keeps it away.
-- Super+Up/Down (window focus) leave an open HUD up but stop a pending one
-- from appearing. Super+Shift+Left/Right move the window with the workspace
-- change, so they show the HUD the same way as Super+Left/Right.
-- XKB: Super 133/134, Tab 23, Left 113, Right 114, Up 111, Down 116.
local SWITCHER_DELAY_MS = 250
local POINTER_SLOP = 4
local super_keys = { [133] = true, [134] = true }
local arrow_keys = { [113] = true, [114] = true }
local tab_key = 23
local window_keys = { [111] = true, [116] = true }
local super_down = {}
local switcher_generation = 0
local switcher_shown = false
local super_press_cursor = nil

local function cursor_pos()
  local ok, pos = pcall(hl.get_cursor_pos)
  if ok and pos and pos.x and pos.y then
    return { x = pos.x, y = pos.y }
  end
  return nil
end

local function pointer_moved_since_press()
  local now = cursor_pos()
  if not super_press_cursor or not now then
    return false
  end
  return math.abs(now.x - super_press_cursor.x) > POINTER_SLOP
    or math.abs(now.y - super_press_cursor.y) > POINTER_SLOP
end

local function switcher_show()
  switcher_generation = switcher_generation + 1
  if not switcher_shown then
    switcher_shown = true
    hl.exec_cmd("omarchy-shell -q io.zet.workspace-switcher hold")
  end
end

local function switcher_hide()
  switcher_generation = switcher_generation + 1
  if switcher_shown then
    switcher_shown = false
    hl.exec_cmd("omarchy-shell -q io.zet.workspace-switcher hide")
  end
end

local function switcher_key(keycode, state)
  if super_keys[keycode] then
    if state == 1 then
      local first = next(super_down) == nil
      super_down[keycode] = true
      if first then
        switcher_generation = switcher_generation + 1
        local mine = switcher_generation
        super_press_cursor = cursor_pos()
        hl.timer(function()
          if mine == switcher_generation and next(super_down) ~= nil and not pointer_moved_since_press() then
            switcher_show()
          end
        end, { timeout = SWITCHER_DELAY_MS, type = "oneshot" })
      end
    elseif state == 0 then
      super_down[keycode] = nil
      if next(super_down) == nil then
        switcher_hide()
      end
    end
  elseif state == 1 and next(super_down) ~= nil then
    if keycode == tab_key or arrow_keys[keycode] then
      switcher_show()
    elseif window_keys[keycode] then
      switcher_generation = switcher_generation + 1
    else
      switcher_hide()
    end
  end
end

hl.on("input.keyboard.key", function(keycode, _, state)
  switcher_key(keycode, state)
end)

-- Start the independent audio backup before Voxtype on either recording key.
hl.unbind("F9")
o.bind("F9", "Start dictation (push-to-talk)", "/home/tyler/.local/bin/voxtype-backup start")
o.bind("F9", "Stop dictation (push-to-talk)", "/home/tyler/.local/bin/voxtype-backup stop", { release = true })
o.bind("CTRL + SPACE", "Toggle dictation", "/home/tyler/.local/bin/voxtype-backup toggle")
o.bind("INSERT", "Reinsert last dictation", "/home/tyler/.local/bin/voxtype-history paste-last")
o.bind("SUPER + SHIFT + V", "Paste last dictation", "/home/tyler/.local/bin/voxtype-history paste-last")
o.bind("SUPER + ALT + V", "Dictation history", "/home/tyler/.local/bin/voxtype-history pick")
o.bind("SUPER + ALT + R", "Transcribe failed dictation again", "/home/tyler/.local/bin/voxtype-history recover")
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

-- Workspace flow: Super+Tab cycles the occupied numbered workspaces; Shift
-- moves the focused window there and follows it.
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Next occupied workspace", "/home/tyler/.local/bin/zet-workspace-flow cycle")
o.bind("SUPER + SHIFT + TAB", "Move window to next occupied workspace", "/home/tyler/.local/bin/zet-workspace-flow cycle move")
-- Replace next-monitor focus with the stock former-workspace action.
hl.unbind("CTRL + ALT + TAB")
o.bind("CTRL + ALT + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))
-- Ctrl+Alt+1..0 select numbered workspaces (Super+1..0 are unbound).
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  hl.unbind("SUPER + " .. key)
  o.bind("CTRL + ALT + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
end
-- Super+Left/Right step to the adjacent numbered workspace (1-10; from HDMI
-- they return to the laptop). Super+Shift+Left/Right take the focused window
-- along. Super+Up/Down take over the stock window focus that Super+Left/Right
-- had. Super+Shift+Up/Down take over the stock left/right window swaps:
-- Up swaps right, Down swaps left.
-- Directional focus and swaps stop at the edge of the monitor instead of
-- reaching across: HDMI-A-1 sits left of the laptop, so a swap at the left
-- edge pulled the X window onto the laptop and pushed a laptop window onto
-- HDMI.
hl.config({ binds = { window_direction_monitor_fallback = false } })
hl.unbind("SUPER + LEFT")
hl.unbind("SUPER + RIGHT")
hl.unbind("SUPER + SHIFT + LEFT")
hl.unbind("SUPER + SHIFT + RIGHT")
hl.unbind("SUPER + UP")
hl.unbind("SUPER + DOWN")
hl.unbind("SUPER + SHIFT + UP")
hl.unbind("SUPER + SHIFT + DOWN")
o.bind("SUPER + LEFT", "Previous workspace", "/home/tyler/.local/bin/zet-workspace-flow left")
o.bind("SUPER + RIGHT", "Next workspace", "/home/tyler/.local/bin/zet-workspace-flow right")
o.bind("SUPER + SHIFT + LEFT", "Move window to previous workspace", "/home/tyler/.local/bin/zet-workspace-flow left move")
o.bind("SUPER + SHIFT + RIGHT", "Move window to next workspace", "/home/tyler/.local/bin/zet-workspace-flow right move")
o.bind("SUPER + UP", "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + DOWN", "Focus on right window", hl.dsp.focus({ direction = "r" }))
o.bind("SUPER + SHIFT + UP", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
o.bind("SUPER + SHIFT + DOWN", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))

-- Only Super+Alt+X changes what HDMI-A-1 shows. Super+scroll steps through
-- the occupied numbered workspaces on the laptop and stops at the first and
-- last; over HDMI it does nothing. Hyprland's e+1/e-1 ran past the last laptop
-- workspace onto HDMI's named views. Super+Shift+Alt+Arrow moved a workspace
-- onto or off that monitor, so it stays unbound. hypr/workspaces.lua and
-- hypr/windows.lua catch any other path.
function zet_super_scroll(direction)
  local monitor = hl.get_monitor_at_cursor()
  if monitor == nil or monitor.name == "HDMI-A-1" then return end
  local active = monitor.active_workspace
  local current = active and active.id or 0
  if current < 1 or current > 10 then return end
  local target = nil
  for _, workspace in ipairs(hl.get_workspaces()) do
    local id = workspace.id
    if id >= 1 and id <= 10 and workspace.windows > 0 then
      if direction > 0 and id > current and (target == nil or id < target) then target = id end
      if direction < 0 and id < current and (target == nil or id > target) then target = id end
    end
  end
  if target ~= nil then
    hl.dispatch(hl.dsp.focus({ workspace = tostring(target) }))
  end
end
hl.unbind("SUPER + mouse_down")
hl.unbind("SUPER + mouse_up")
o.bind("SUPER + mouse_down", "Scroll active workspace forward", function() zet_super_scroll(1) end)
o.bind("SUPER + mouse_up", "Scroll active workspace backward", function() zet_super_scroll(-1) end)
for _, direction in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
  hl.unbind("SUPER + SHIFT + ALT + " .. direction)
end

-- Note: SUPER+CTRL+O was previously bound to Toggle menu. Replaced with the
-- bar to-do list. Super+Space opens the Omarchy menu.
hl.unbind("SUPER + CTRL + O")
o.bind("SUPER + CTRL + O", "To-do list", "omarchy-shell -q io.zet.todo-list toggle")
o.bind("SUPER + CTRL + X", "Post to X", "/home/tyler/.local/bin/zet-x-compose")
o.bind("SUPER + ALT + X", "HDMI views", "/home/tyler/.local/bin/zet-hdmi-view")
o.bind("SUPER + ALT + C", "Cue sheet", "/home/tyler/.local/bin/zet-cue-sheet")

-- File Search overlay (localsearch full-text). Replaces Omarchy Find on Alt+Space.
-- Super+Space is the Omarchy menu.
o.bind("ALT + SPACE", "File search", "omarchy-shell -q shell toggle io.github.corck.filesearch '{}'")


-- Ibara workstation panel. SUPER+I was free.
o.bind("SUPER + I", "ibara", "omarchy-shell -q shell toggle io.zet.ibara '{}'")


-- strata-installer: file-manager start
hl.unbind("SUPER + SHIFT + F")
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = "/home/tyler/.local/bin/strata" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
  "uwsm-app -- /home/tyler/.local/bin/strata \"$(omarchy-cmd-terminal-cwd)\"")
-- strata-installer: file-manager end
