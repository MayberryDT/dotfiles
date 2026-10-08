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
- Brave Origin flags
- Violet Current theme palette

The shell layout references separately installed community plugins. The active
theme is recorded in `omarchy/current-theme.txt`; install themes and plugins
through Omarchy before applying the corresponding settings.

Violet Current's palette is included at
`home/.config/omarchy/themes/violet-current/colors.toml`. Its wallpaper artwork
is maintained separately and excluded from this configuration mirror, along
with screenshots and personal portrait assets. Add your preferred backgrounds
to `~/.config/omarchy/themes/violet-current/backgrounds/` before selecting it.

The Voxtype keybindings use `~/.local/bin/voxtype-backup` to save local FLAC
audio during dictation. The helper is included; recordings under
`~/.local/share/voxtype/recordings/` are private runtime data and are excluded.

The numbered-workspace keys use `~/.local/bin/zet-workspace-flow`, which is
included. Each workspace number spans two monitors: Hyprland workspace N on the
left monitor and N+10 on the right, switched together.
`.config/hypr/workspaces.lua` names the two outputs (`eDP-2`, `HDMI-A-1`)
for their starting workspaces; change them to match your hardware. The
`tyler.workspaces` bar indicator calls the same helper. The switcher overlay it
refreshes (`io.zet.workspace-switcher`) is not part of this mirror; without it,
the helper still works.

The desktop sound helper `~/.local/bin/juice-sound` and each pack's `notify.wav`
cue are included. Discord uses this shared notification cue, including for urgent
messages. The rest of the desktop sound packs are maintained separately.

## Layout

Files under `home/` mirror paths relative to `$HOME`. Review every file before
using it on another machine; several settings are intentionally personal and
hardware-specific even though secrets and private runtime data are excluded.

## Maintenance

Run `./scripts/sync-from-home`, review the diff, and run
`./scripts/check-public` before committing. Finalized changes are committed and
pushed to `main`; the local Omarchy workspace instructions enforce that rule.
