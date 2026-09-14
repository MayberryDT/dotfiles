# Tyler's Omarchy dotfiles

The public, curated configuration for Tyler's Omarchy 4 daily-driver desktop.
It is intended as a reference for the Omarchy Guild rather than a turnkey
installer: hardware-specific monitor settings, private data, runtime state,
backups, media, credentials, and third-party plugin source are excluded.

## Included

- Hyprland configuration and keybindings
- Omarchy shell layout and extension settings
- Custom hooks and the small `tyler.*` shell plugins
- Alacritty, Foot, Ghostty, Kitty, and btop configuration

The shell layout references separately installed community plugins. The active
theme is recorded in `omarchy/current-theme.txt`; install themes and plugins
through Omarchy before applying the corresponding settings.

## Layout

Files under `home/` mirror paths relative to `$HOME`. Review every file before
using it on another machine; several settings are intentionally personal and
hardware-specific even though secrets and private runtime data are excluded.

## Maintenance

Run `./scripts/sync-from-home`, review the diff, and run
`./scripts/check-public` before committing. Finalized changes are committed and
pushed to `main`; the local Omarchy workspace instructions enforce that rule.
