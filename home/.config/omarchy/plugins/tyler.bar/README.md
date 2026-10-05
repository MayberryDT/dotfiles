# Omarchy bar

This is the Quickshell implementation of the Omarchy status bar. It is
shipped as a first-party plugin of [`omarchy-shell`](../../README.md), the
long-running shell host. The bar is mounted at startup and lives inside
the shell for its whole session.

- `manifest.json` declares the plugin (`id: omarchy.bar`, `kind: bar`) and points at `Bar.qml` as the entry point.
- `Bar.qml` is Omarchy-owned bar engine code, loaded by the omarchy-shell host. Users should not edit it directly.
- `widgets/` holds simple first-party bar widgets with sibling manifests.
- Feature plugins such as `../panels/audio/`, `../panels/network/`, `../panels/power/`, and `../agents/` provide richer popup bar plugins.
- The bar receives its config from the host shell as a `barConfig` property; the host loads it from `~/.config/omarchy/shell.json` (or `config/omarchy/shell.json` when the user has no file).
- `omarchy bar position` updates only the user shell.json file.

## Customizing

The bar config lives under the `bar:` key of [`~/.config/omarchy/shell.json`](../../README.md#shelljson-shape). Out of the box the shell uses [`config/omarchy/shell.json`](../../../config/omarchy/shell.json). Once you customize anything via the bar gestures, `omarchy bar ...`, or by editing shell.json directly, your file is canonical — there is no deep-merge.

The bar is configured directly on the bar itself: drag empty bar space (or click-and-hold) to move the bar to another screen edge, double-left-click empty center-bar space to toggle transparency, and drag widgets to reorder them. The `omarchy bar position`, `omarchy bar transparent`, `omarchy bar move`, and `omarchy bar set` commands do the same from scripts. Enable or disable widgets with `omarchy plugin enable` and `omarchy plugin disable` (widget ids come from `omarchy plugin list`).

Example `shell.json` (bar subtree only shown):

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left": [
        { "id": "omarchy.menu" },
        { "id": "omarchy.spacer", "size": 12 },
        { "id": "omarchy.workspaces" }
      ],
      "center": [
        { "id": "omarchy.media" },
        { "id": "omarchy.clock", "format": "HH:mm" }
      ],
      "right": [
        { "id": "omarchy.audio" },
        { "id": "omarchy.power" }
      ]
    }
  }
}
```

`centerAnchor` pins one center module to the exact horizontal/vertical center and flanks others around it. Set to an empty string to disable anchoring (the center list is centered as a group).

## Module catalogue

### First-party interactive widgets

| Name | What it does | Interactions |
|---|---|---|
| `omarchy.menu` | Omarchy menu launcher | left = menu · right = terminal |
| `omarchy.workspaces` | Hyprland workspace switcher | left = focus workspace |
| `omarchy.clock` | Date/time label + popup with a month grid, ISO week numbers, and month stepping | left = popup · right = cycle label format · middle = timezone selector |
| `omarchy.media` | MPRIS now-playing — scrolling track + artist, cover-art popup | left = play/pause · middle = next · scroll = prev/next · right = popup |
| `omarchy.indicators` | Manual state indicators | left = indicator action |
| `omarchy.system-update` | Available update indicator | left = update |
| `omarchy.tray` | System tray | hover = reveal drawer · right on chevron = manage |
| `omarchy.weather` | Weather icon + popup with forecast | left = popup · right = full notification |
| `omarchy.microphone` | Mic icon + scroll volume | left = mute toggle · middle = audio panel · scroll = source volume |

| `omarchy.audio` | Volume icon + popup with master slider, output-device picker, per-app mixer | left = popup · right = mute · middle = popup · scroll = volume |
| `omarchy.network` | Wi-Fi/Ethernet icon + popup with Wi-Fi scan, signal, connect, DNS provider selection | left = popup |
| `omarchy.tailscale` | Tailscale status, connection switcher, machine browser, and copy actions | left = popup · right = toggle · middle = refresh |
| `omarchy.agents` | AI coding agent limits with pace, today, last week, and all-time model breakdown | left = panel · right = launch agent · middle = next subscription |
| `omarchy.power` | Battery/AC icon + popup with battery stats, power profiles, and system info | left = popup · right = toggle percentage |
| `omarchy.bluetooth` | Bluetooth icon + popup with device list, connect/disconnect, battery | left = popup · right = toggle radio |
| `omarchy.monitor` | Brightness and laptop display controls | left = popup |

The `omarchy.indicators` widget loads individual bar indicators from `indicators/`. Omit `items` (or set it to an empty array) to show all indicators in the default order, or set `items` to a subset such as `["Dnd", "Reminder", "NightLight"]`. Set `alwaysShow` to `true` to keep inactive indicators visible instead of revealing them only on hover. Multiple `omarchy.indicators` instances are allowed, so different sections can show different subsets.

The recording indicator left-click starts or stops capture. Right-click toggles `audioOnly` on this widget: video with webcam, or mixed desktop and microphone audio with no picture.

## Orientation

All widgets work in `top`, `bottom`, `left`, and `right` positions. Popups anchor on the side opposite the bar edge, sliding into the workspace. Vertical bars use 28px width; widgets that show text fall back to compact icon-only forms (e.g. `media` hides its scrolling label).

## Custom user modules

The schema accepts arbitrary module ids that you provide. Set `type` to `command` for shell-driven output or `qml` for a custom QML widget. Both still go under `bar.layout.<section>` in `shell.json`.

Command module:

```json
{
  "version": 1,
  "bar": {
    "layout": {
      "right": [
        { "id": "omarchy.tray" },
        { "id": "vpn", "type": "command", "exec": "~/.config/omarchy/bar/scripts/vpn-status", "interval": 5, "tooltip": "VPN", "onClick": "nm-connection-editor" },
        { "id": "omarchy.audio" }
      ]
    }
  }
}
```

The command may print plain text or Waybar-style JSON, for example:

```json
{"text":"󰌆","tooltip":"Work VPN","class":"active"}
```

QML module:

```json
{
  "version": 1,
  "bar": {
    "layout": {
      "right": [
        { "id": "gpu", "type": "qml" },
        { "id": "omarchy.audio" }
      ]
    }
  }
}
```

Then create `~/.config/omarchy/bar/modules/gpu.qml`. If you want to store it elsewhere, add a `source` path.

Custom QML modules should be an `Item` with `implicitWidth` and `implicitHeight`. They may optionally define these properties, which the bar fills after loading:

```qml
import QtQuick

Item {
  property var bar
  property string moduleName
  property var settings

  implicitWidth: 28
  implicitHeight: bar ? bar.barSize : 26

  Text {
    anchors.centerIn: parent
    text: "GPU"
    color: bar ? bar.foreground : "white"
    font.family: bar ? bar.fontFamily : "monospace"
    font.pixelSize: 12
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (bar) bar.run("omarchy-launch-or-focus-tui btop")
  }
}
```

## Bar properties available to widgets

Widgets receive `bar` (the shell root), `moduleName` (string), and `settings` (object) injected at load time. The bar exposes:

- `bar.foreground`, `bar.background`, `bar.urgent` — theme colors (live-updated)
- `bar.fontFamily` — current monospace family
- `bar.position` — `"top" | "bottom" | "left" | "right"`
- `bar.vertical` — boolean shortcut
- `bar.barSize` — 26 horizontal / 28 vertical
- `bar.run(command)` — fire-and-forget bash exec
- `bar.shellQuote(value)` — safe shell-quote a string
- `bar.showTooltip(target, text)` / `bar.hideTooltip(target)` — shared tooltip popup
- `bar.requestPopout(owner)` / `bar.releasePopout(owner)` — one-popup-at-a-time coordinator

First-party bar widgets are manifest-backed just like third-party widgets.
Simple widgets carry sibling manifests such as `widgets/Workspaces.manifest.json`;
richer popup plugins live in feature directories such as `../panels/audio/`,
`../panels/network/`, and `../agents/`; and feature plugins such as
`omarchy.menu` and `omarchy.media` declare their bar-widget entry points in their own
`manifest.json`. Bar layout ids are namespaced, e.g. `omarchy.audio`,
`omarchy.network`, and `omarchy.clock`. Older UpperCamelCase ids such as
`AudioPanel` and `Clock` are migrated forward; new configs should use the
namespaced ids.

Third-party widgets ship as separate plugins under
`~/.config/omarchy/plugins/<plugin-id>/` with their own `manifest.json`
declaring `kinds: ["bar-widget"]` and a `barWidget` entry point. See
[../../README.md](../../README.md) for the manifest schema. Rescan, enable,
and place third-party plugins with `omarchy-shell shell rescanPlugins`,
`omarchy plugin enable`, and `omarchy bar move`.

## Juice (tyler.bar)

This clone adds drawers, attention, modes and a power-up. It imports motion
timings from `../tyler.juice/Motion.js`, so the `tyler.juice` plugin must be
installed alongside it.

### Drawers

`bar.drawers` groups widgets behind one quiet mark. Every member stays an
ordinary `bar.layout.*` entry (the host enables, configures and moves widgets
by those entries); the drawer only names them:

```json
"drawers": {
  "tyler.systems": { "label": "Systems", "mark": "dot", "members": ["omarchy.network", "omarchy.audio"] }
}
```

Put `{"id": "tyler.systems"}` in the layout where the mark should sit, with its
members next to it on the side facing the centre. At rest only the mark shows
(`muted`). Clicking the mark unfolds the drawer inline along the bar; members
fade in nearest-first within about 150 ms. Hovering never opens a drawer, so a
pointer passing along the bar moves nothing. An opened drawer stays open
(including while a member's popup panel has the pointer) until the mark is
clicked again. Only one drawer is out at a time. A folded member takes no
clicks: a click only reaches widgets inside the slot that was clicked. Members
stay loaded while folded. A drawer without a mark on a bar shows its members
normally.

### Attention

`Attention.js` reads each widget's own state and answers 0 (quiet), 1 (needs a
look or has news: `accent`) or 2 (broken or blocked: `urgent`). A member with
attention stays out of its folded drawer, and the mark takes the strongest
colour among its members. Hovering the mark lists the reasons. Rises wait 1.5 s
before counting, so services still starting up never flash trouble. Any widget
can join without an adapter by exposing `juiceAttention` (0–2) and
`juiceAttentionReason` on its root item.

Indicators count when Stay Awake, Do Not Disturb, Screen Recording, Dictation
or a Reminder is on. Night Light never counts: it is the normal evening state.

`{"id": "tyler.scratchpad"}` is an engine-drawn, trouble-only item: the icon of
an app on `special:scratchpad` that wants attention, in `urgent`. Clicking it
shows the scratchpad.

### Modes

`bar.modes` (all optional):

- `focus.keep`: ids that stay during focus mode (`focus.on` on the juice state
  bus). The centre anchor and anything with attention always stay; drawer marks
  hide.
- `meeting.promote`: ids brought out of drawers (and kept in focus) during a
  meeting. A meeting is a running timed event in `meeting.calendar` (default
  `tmn73.calendar`) that has a meeting link or an RSVP, a recording in
  `meeting.recorder` (default `jankeesvw.meeting-recorder`), or `meeting.on` on
  the state bus. `meeting.enabled: false` turns it off.
- `away.minutes` (default 5) and `away.opacity` (default 0.15): after that long
  without input (idle inhibitors respected), the bar fades down to that opacity.
  `away.enabled: false` turns it off.

Mode changes use `Motion.settle`. With `"motion": "reduced"` on the state bus,
everything jumps to its end state.

### Power-up

Once per login (marker `$XDG_RUNTIME_DIR/tyler-juice/bar-powered-up`), the bar's
widgets appear left to right (top to bottom on a vertical bar) over about a
second. Shell reloads and restarts skip it.

### Testing

`$XDG_RUNTIME_DIR/tyler-juice/fake-attention.json`, read only while it exists:

```json
{ "omarchy.network": 2, "omamail": 1, "tyler.scratchpad": 2, "@meeting": true, "@focus": true, "@away": true }
```

`omarchy-shell omarchy.bar juice` prints the modes, the power-up phase and each
slot's drawer, attention and whether it is drawn.

`omarchy-shell omarchy.bar drawer <id> <open|close|toggle|pin>` drives a drawer
on the focused monitor's bar without a pointer and returns its new state.
`open` keeps it out for 4 s (longer while the pointer is on it), `close` unpins
and folds it, `pin` holds it open until `close` or a click on the mark.
