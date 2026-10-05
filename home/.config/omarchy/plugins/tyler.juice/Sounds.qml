import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth

// Sounds for what the desktop does that no script of ours announces:
// workspace switches and carried windows, the scratchpad and drop-downs,
// fullscreen and floating, the mic, dictation, screen recording, the clipboard,
// the charger, Bluetooth, the network and Tailscale, and a meeting about to
// start. Each fires on a change, never for the state found at startup.
// juice-sound decides whether a sound may play right now.
Item {
  id: sounds

  property var service: null
  // Nothing plays until the watchers have read the state they start from.
  property bool armed: false

  function play(name) {
    if (armed && service) service.sound(name)
  }

  function now() { return Date.now() }

  Timer {
    interval: 4000
    running: true
    onTriggered: sounds.armed = true
  }

  // ---------------------------------------------------------- Hyprland

  property int lastWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
  property string lastMonitor: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  property int pendingWorkspace: 0
  property double movedAt: 0
  property int movedTo: 0
  property double specialAt: 0
  property double openedAt: 0
  property var specialOn: ({})   // monitor -> shown special workspace name

  function dropdownName(special) {
    return special === "special:quick" || special === "special:music"
  }

  function onSpecial(name, monitor) {
    var before = specialOn[monitor] || ""
    if (name === before) return
    var next = Object.assign({}, specialOn)
    next[monitor] = name
    specialOn = next
    specialAt = now()
    var which = name || before
    var shown = name !== ""
    if (dropdownName(which)) play(shown ? "dropdown-down" : "dropdown-up")
    else play(shown ? "scratchpad-show" : "scratchpad-hide")
  }

  function hyprEvent(name, data) {
    var parts = String(data || "").split(",")
    if (name === "workspacev2") {
      pendingWorkspace = parseInt(parts[0], 10) || 0
      workspaceSettle.restart()
    } else if (name === "movewindowv2") {
      var to = parseInt(parts[1], 10) || 0
      if (to > 0) {
        movedAt = now()
        movedTo = to
        carrySettle.restart()
      }
    } else if (name === "activespecial") {
      onSpecial(parts[0] || "", parts[1] || "")
    } else if (name === "openwindow") {
      openedAt = now()
    } else if (name === "fullscreen") {
      if (now() - specialAt > 400) play("fullscreen")
    } else if (name === "changefloatingmode") {
      if (now() - specialAt > 400 && now() - openedAt > 500) play("float")
    }
  }

  // Hyprland reports a workspace and a monitor change separately, so look at
  // the settled result: a different monitor is a pointer crossing, not a switch.
  function settleWorkspace() {
    var to = pendingWorkspace
    var monitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var from = lastWorkspace
    var sameMonitor = monitor === lastMonitor
    lastWorkspace = to
    lastMonitor = monitor
    if (!sameMonitor || to <= 0 || from <= 0 || to === from) return
    var direction = to > from ? "right" : "left"
    var carried = movedTo === to && now() - movedAt < 300
    if (carried) {
      carrySettle.stop()
      movedTo = 0
    }
    play((carried ? "ws-carry-" : "ws-") + direction)
  }

  // A window sent to another workspace without following it. When the
  // workspace is changing too, that settle plays the carry instead.
  function settleCarry() {
    if (workspaceSettle.running) return
    var to = movedTo
    movedTo = 0
    if (to <= 0 || to === lastWorkspace || now() - specialAt < 400) return
    play("ws-carry-" + (to > lastWorkspace ? "right" : "left"))
  }

  Timer { id: workspaceSettle; interval: 45; onTriggered: sounds.settleWorkspace() }
  Timer { id: carrySettle; interval: 120; onTriggered: sounds.settleCarry() }

  Connections {
    target: Hyprland
    function onRawEvent(event) { sounds.hyprEvent(event.name, event.data) }
  }

  // ---------------------------------------------------------------- mic

  readonly property var micSource: Pipewire.defaultAudioSource
  readonly property bool micMuted: !!micSource && !!micSource.audio && micSource.audio.muted
  property double micSourceAt: 0

  PwObjectTracker { objects: sounds.micSource ? [sounds.micSource] : [] }

  onMicSourceChanged: micSourceAt = now()
  onMicMutedChanged: Qt.callLater(function() {
    // Switching to another mic is not a mute; both changes land together.
    if (now() - micSourceAt < 1000) return
    play(micMuted ? "mic-mute" : "mic-unmute")
  })

  // ----------------------------------------------------------- dictation

  property string dictation: ""

  function readDictation(line) {
    var state = ""
    try {
      var data = JSON.parse(line)
      state = String(data.alt || data.class || "idle")
    } catch (e) { return }
    var before = dictation
    dictation = state
    if (before === "") return
    if (state === "recording" && before !== "recording") play("dictation-start")
    else if (before === "recording" && state !== "recording") play("dictation-stop")
  }

  Process {
    id: voxtype
    running: true
    command: ["voxtype", "status", "--follow", "--extended", "--format", "json"]
    stdout: SplitParser { onRead: function(line) { sounds.readDictation(line) } }
    onExited: { sounds.dictation = ""; restartVoxtype.start() }
  }
  Timer { id: restartVoxtype; interval: 30000; onTriggered: voxtype.running = true }

  // ------------------------------------------------------ screen recording

  property int recording: -1   // -1 unknown, 0 no, 1 yes

  Process {
    id: recordingProbe
    command: ["pgrep", "-f", "^gpu-screen-recorder"]
    onExited: function(code) {
      var next = code === 0 ? 1 : 0
      var before = sounds.recording
      sounds.recording = next
      if (before !== -1 && before !== next) sounds.play(next ? "record-start" : "record-stop")
    }
  }
  Timer { interval: 1500; running: true; repeat: true; onTriggered: recordingProbe.running = true }

  // ------------------------------------------------------------ clipboard

  property double clipboardStarted: 0
  property double lastCopy: 0

  Process {
    id: clipboardWatch
    running: true
    command: ["wl-paste", "--watch", "echo", "copied"]
    onStarted: sounds.clipboardStarted = sounds.now()
    stdout: SplitParser {
      onRead: function() {
        var t = sounds.now()
        // wl-paste reports the selection it finds on start; that is not a copy.
        if (t - sounds.clipboardStarted < 800 || t - sounds.lastCopy < 250) return
        sounds.lastCopy = t
        sounds.play("copy")
      }
    }
    onExited: restartClipboard.start()
  }
  Timer { id: restartClipboard; interval: 5000; onTriggered: clipboardWatch.running = true }

  // -------------------------------------------------------------- charger

  readonly property bool onBattery: UPower.onBattery
  onOnBatteryChanged: play(onBattery ? "charger-out" : "charger-in")

  // ------------------------------------------------------------ Bluetooth

  Variants {
    model: Bluetooth.devices ? Bluetooth.devices.values : []
    delegate: Item {
      required property var modelData
      readonly property bool connected: !!modelData && modelData.connected === true
      onConnectedChanged: sounds.play(connected ? "bt-connect" : "bt-disconnect")
    }
  }

  // -------------------------------------------------- network and Tailscale

  property string connectivity: ""

  Process {
    id: networkWatch
    running: true
    command: ["nmcli", "monitor"]
    stdout: SplitParser {
      onRead: function(line) {
        var match = /Connectivity is now '([a-z]+)'/.exec(String(line))
        if (!match) return
        var next = match[1] === "full" ? "up" : "down"
        var before = sounds.connectivity
        sounds.connectivity = next
        // The first report is where we start from, unless it's a drop.
        if (before === "" ? next === "down" : before !== next) sounds.play(next === "up" ? "net-up" : "net-down")
      }
    }
    onExited: restartNetwork.start()
  }
  Timer { id: restartNetwork; interval: 30000; onTriggered: networkWatch.running = true }

  property string tailscale: ""

  Process {
    id: tailscaleProbe
    command: ["tailscale", "status", "--json", "--peers=false"]
    stdout: StdioCollector {
      onStreamFinished: {
        var next = ""
        try { next = JSON.parse(text).BackendState === "Running" ? "up" : "down" } catch (e) { return }
        var before = sounds.tailscale
        sounds.tailscale = next
        if (before !== "" && before !== next) sounds.play(next === "up" ? "net-up" : "net-down")
      }
    }
  }
  Timer { interval: 20000; running: true; repeat: true; triggeredOnStart: true; onTriggered: tailscaleProbe.running = true }

  // ------------------------------------------------- meeting in a minute

  readonly property string calendarPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/calendar-events.json"
  property var calendar: []
  property var announced: ({})

  FileView {
    path: sounds.calendarPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        sounds.calendar = Array.isArray(data.events) ? data.events : []
      } catch (e) {}
    }
  }

  function checkMeetings() {
    var t = now()
    for (var i = 0; i < calendar.length; i++) {
      var e = calendar[i]
      if (!e || e.allDay || e.responseStatus === "declined") continue
      var start = Date.parse(e.start)
      if (!isFinite(start)) continue
      var key = String(e.id) + "@" + start
      var lead = start - t
      if (lead > 0 && lead <= 75000 && !announced[key]) {
        var next = Object.assign({}, announced)
        next[key] = true
        announced = next
        play("meeting-soon")
      }
    }
  }

  Timer { interval: 15000; running: true; repeat: true; onTriggered: sounds.checkMeetings() }
}
