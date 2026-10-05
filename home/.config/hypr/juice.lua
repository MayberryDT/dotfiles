-- Desktop juice: loads each slice's Hyprland file if it exists.
-- Loaded last from hyprland.lua so it applies after Omarchy and Atmos.
local slices = { "focus", "media", "herdr", "moments" }
local dir = (os.getenv("HOME") or "") .. "/.config/hypr/juice/"

for _, name in ipairs(slices) do
  local file = io.open(dir .. name .. ".lua", "r")
  if file then
    file:close()
    require("hypr.juice." .. name)
  end
end
