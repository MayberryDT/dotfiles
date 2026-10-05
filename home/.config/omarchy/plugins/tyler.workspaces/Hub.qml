import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "WorkspaceNames.js" as Names
import "HubBridge.js" as HubBridge

// The plugin's one always-loaded instance (overlay entry, keepLoaded). It owns
//   - the `tyler.workspaces` IPC target: `peek true|false` from the Super-hold
//     binding in ~/.config/hypr/juice/workspaces.lua, plus `names`/`state`;
//   - the derived workspace model every bar instance reads, so names are
//     worked out once rather than once per monitor;
//   - the state bus reader (Herdr agents, reduced motion).
// It has no window of its own: the peek labels are drawn by each bar's
// indicator row, which is the only thing that knows where its workspaces sit.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  property bool peeking: false
  readonly property bool opened: peeking

  // id -> Names.describeWorkspace() result, only for workspaces with windows.
  property var workspaces: ({})
  property string workspacesKey: ""
  property var bus: null
  readonly property bool reducedMotion: Names.reducedMotion(bus)
  readonly property string busPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tyler-juice/state.json"
  property bool busLoaded: false

  function recompute() {
    fastRecompute.stop()
    slowRecompute.stop()
    var next = Names.collect(Hyprland, DesktopEntries, root.bus)
    var key = JSON.stringify(next)
    if (key === root.workspacesKey) return
    root.workspacesKey = key
    root.workspaces = next
  }

  // Focus, windows opening and urgency land quickly; title changes (agent
  // spinners, shells printing the cwd) are coalesced into a slower beat.
  function scheduleFast() { if (!fastRecompute.running) fastRecompute.start() }
  function scheduleSlow() { if (!slowRecompute.running) slowRecompute.start() }

  function setPeek(on) {
    if (on) {
      root.recompute()
      failsafe.restart()
    } else {
      failsafe.stop()
    }
    root.peeking = on
  }

  function parseFlag(value) {
    var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
    return text === "true" || text === "1" || text === "on" || text === "yes"
  }

  // Host lifecycle: `omarchy-shell shell summon|hide|toggle tyler.workspaces`.
  function open(payloadJson) { root.setPeek(true) }
  function close() { root.setPeek(false) }

  Timer { id: fastRecompute; interval: 50; onTriggered: root.recompute() }
  Timer { id: slowRecompute; interval: 300; onTriggered: root.recompute() }
  // A window that has just opened has no class until the client list is
  // re-read, so its icon is only known after the refresh lands.
  Timer {
    id: toplevelRefresh
    interval: 250
    onTriggered: {
      Hyprland.refreshToplevels()
      slowRecompute.restart()
    }
  }

  // A release the compositor never reported must not strand the labels.
  Timer { id: failsafe; interval: 15000; onTriggered: root.peeking = false }

  // The bus may appear after the shell starts (tyler.juice writes it); a
  // FileView cannot watch a file that does not exist yet.
  Timer {
    interval: 5000
    repeat: true
    running: !root.busLoaded
    onTriggered: busFile.reload()
  }

  FileView {
    id: busFile
    path: root.busPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.busLoaded = true
      var next = Names.parseBus(text(), root.bus)
      if (next !== root.bus) {
        root.bus = next
        root.scheduleFast()
      }
    }
    onLoadFailed: root.busLoaded = false
  }

  Connections {
    target: Hyprland

    function onActiveToplevelChanged() { root.scheduleFast() }
    function onFocusedWorkspaceChanged() { root.scheduleFast() }

    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "windowtitle" || name === "windowtitlev2") {
        root.scheduleSlow()
        return
      }
      if (name === "openwindow" || name === "closewindow" || name.indexOf("movewindow") === 0) {
        toplevelRefresh.restart()
        root.scheduleFast()
        return
      }
      if (name === "urgent" || name.indexOf("activewindow") === 0 || name.indexOf("workspace") !== -1)
        root.scheduleFast()
    }
  }

  Connections {
    target: DesktopEntries
    function onApplicationsChanged() { root.scheduleSlow() }
  }

  IpcHandler {
    target: "tyler.workspaces"

    // Super-hold peek. The 350 ms hold delay lives in the Hyprland binding.
    function peek(state: string): string {
      root.setPeek(root.parseFlag(state))
      return root.peeking ? "on" : "off"
    }

    // {"1":"rat-detective","2":"juice",...}: occupied workspaces only.
    function names(): string {
      var out = ({})
      for (var id in root.workspaces) out[id] = root.workspaces[id].name
      return JSON.stringify(out)
    }

    function state(): string {
      var out = ({})
      for (var id in root.workspaces) {
        var info = root.workspaces[id]
        out[id] = { name: info.name, kind: info.kind, windows: info.count, attention: info.attention }
      }
      return JSON.stringify({ peeking: root.peeking, motion: root.reducedMotion ? "reduced" : "full", workspaces: out })
    }
  }

  Component.onCompleted: {
    HubBridge.publish(root)
    root.recompute()
  }
  Component.onDestruction: HubBridge.clear(root)
}
