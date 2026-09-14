import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property bool recording: false
  readonly property bool audioOnly: !!(root.indicatorHost && root.indicatorHost.settings && root.indicatorHost.settings.audioOnly === true)

  active: recording
  activeText: audioOnly ? "󰺢" : "󰻂"
  inactiveText: audioOnly ? "󰺢" : "󰻂"
  activeTooltipText: audioOnly ? "Stop audio recording" : "Stop recording"
  inactiveTooltipText: audioOnly ? "Record desktop and mic audio · right-click for video" : "Record YouTube video · right-click for audio only"

  function refresh() {
    if (!root.bar || statusProc.running) return
    statusProc.command = ["pgrep", "--quiet", "-f", "^gpu-screen-recorder|^omarchy-youtube-audio-record"]
    statusProc.running = true
  }

  function persistAudioOnly(enabled) {
    var host = root.indicatorHost
    if (!host || !root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var next = { id: host.moduleName || "omarchy.indicators", audioOnly: enabled }
    var current = host.settings
    if (current) {
      if (current.items !== undefined) next.items = current.items
      if (current.alwaysShow !== undefined) next.alwaysShow = current.alwaysShow
    }
    host.settings = next
    root.bar.shell.updateEntryInline(next.id, next)
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: statusProc
    onExited: function(exitCode) {
      root.recording = exitCode === 0
    }
  }

  onPressed: function(button) {
    if (button === Qt.RightButton) {
      if (!root.recording) persistAudioOnly(!root.audioOnly)
      return
    }
    if (root.bar) {
      root.bar.run(root.audioOnly ? "/home/tyler/YouTube/bin/record --audio-only" : "/home/tyler/YouTube/bin/record")
    }
  }
}
