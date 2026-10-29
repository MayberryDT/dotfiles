{
  "name": "Omarchy",
  "appearance": "{{ mode }}",
  "canvas": "{{ background }}",
  "accent": "{{ accent }}",
  "colors": {
    "chrome": "{{ background }}",
    "toolbar": "{{ background }}",
    "toolbarForeground": "{{ foreground }}",
    "toolbarBorder": "{{ muted }}",

    "text": "{{ foreground }}",
    "border": "{{ muted }}",
    "focus": "{{ accent }}",

    "surface": "{{ background }}",
    "surfaceRaised": "{{ mix background foreground 8% }}",
    "surfaceOverlay": "{{ mix background foreground 4% }}",
    "input": "{{ muted }}",
    "muted": "{{ mix background foreground 5% }}",
    "secondary": "{{ mix background foreground 10% }}",

    "sidebar": "{{ dark_background }}",
    "sidebarForeground": "{{ foreground }}",
    "sidebarBorder": "{{ muted }}",
    "sidebarRowHover": "{{ mix dark_background foreground 6% }}",
    "sidebarRowActive": "{{ mix dark_background accent 18% }}",
    "sidebarRowSelected": "{{ selection }}",

    "error": "{{ mix red foreground 35% }}",
    "warning": "{{ mix yellow foreground 35% }}",

    "codeBackground": "{{ dark_background }}",
    "codeForeground": "{{ foreground }}",

    "terminalBackground": "{{ background }}",
    "terminalForeground": "{{ foreground }}",
    "terminalCursor": "{{ bright_foreground }}",
    "terminalSelection": "{{ selection }}",
    "terminalScrollbar": "{{ muted }}",
    "terminalScrollbarHover": "{{ dark_foreground }}"
  }
}
