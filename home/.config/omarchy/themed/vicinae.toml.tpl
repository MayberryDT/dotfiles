# Generated from the active Omarchy colors.toml. A theme that ships its own
# vicinae.toml is left alone.
[meta]
version = 1
name = "Omarchy"
description = "Follows the current Omarchy theme."
variant = "{{ mode }}"
inherits = "vicinae-{{ mode }}"

[colors.core]
accent = "{{ accent }}"
accent_foreground = "{{ selection_foreground }}"
background = "{{ background }}"
foreground = "{{ foreground }}"
secondary_background = "{{ dark_background }}"
border = "{{ lighter_background }}"

[colors.main_window]
border = "{{ lighter_background }}"

[colors.settings_window]
border = "{{ lighter_background }}"

[colors.accents]
blue = "{{ blue }}"
green = "{{ green }}"
magenta = "{{ magenta }}"
orange = "{{ orange }}"
red = "{{ red }}"
yellow = "{{ yellow }}"
cyan = "{{ cyan }}"
purple = "{{ purple }}"

[colors.text]
default = "{{ foreground }}"
muted = "{{ muted }}"
danger = "{{ red }}"
success = "{{ green }}"
placeholder = "{{ dark_foreground }}"
selection = { background = "{{ selection }}", foreground = "{{ selection_foreground }}" }

[colors.input]
border = "{{ lighter_background }}"
border_focus = "{{ accent }}"
border_error = "{{ red }}"

[colors.list.item.hover]
background = "{{ mix background foreground 8% }}"
foreground = "{{ foreground }}"
secondary_foreground = "{{ dark_foreground }}"

[colors.list.item.selection]
background = "{{ selection }}"
foreground = "{{ selection_foreground }}"
secondary_background = "{{ selection }}"
secondary_foreground = "{{ selection_foreground }}"

[colors.loading]
bar = "{{ accent }}"
spinner = "{{ foreground }}"
