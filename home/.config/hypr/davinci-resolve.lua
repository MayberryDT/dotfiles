-- DaVinci Resolve window policy for this laptop.
--
-- Omarchy's packaged rules (default.hypr.apps.davinci-resolve) float every
-- Resolve window and put the *main* window into fullscreen. Fullscreen is the
-- real problem: it covers the Omarchy bar's reserved zone, so clicks aimed at
-- Resolve's own menu bar land on the bar and the menu cannot be reached.
--
-- The float has to stay for every other Resolve window, though. Resolve is a Qt
-- app whose dropdown menus, combo boxes and dialogs are separate windows of the
-- same `resolve` class; if they are tiled instead of floated they are laid out as
-- panes and become unusable. So this override is deliberately scoped by TITLE to
-- the main window only -- the same match the packaged fullscreen rule uses.
--
-- Net effect: the main window is tiled and never fullscreened, so it sits in the
-- space under the bar with its menus reachable, while popups still float.
--
-- Delete this file and its require() in hyprland.lua to revert to packaged
-- behaviour.

o.window({ class = ".*[Rr]esolve.*", title = "^DaVinci Resolve( Studio)? - .+$" }, {
  tag = "-default-opacity",
  opacity = "1 1",
  float = false,
  fullscreen = false,
  stay_focused = false,
})
