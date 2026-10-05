import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "ServiceBridge.js" as ServiceBridge

// Singleton owner of focus mode, the Herdr herd summary and the state bus
// ($XDG_RUNTIME_DIR/tyler-juice/state.json) read by the other juice plugins.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tyler-juice"
  readonly property string statePath: runtimeDir + "/state.json"
  readonly property string settingsDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/tyler-juice"
  readonly property string settingsPath: settingsDir + "/settings.json"
  readonly property string binDir: home + "/.local/bin"

  // Persistent preferences.
  property string motion: "full"
  property string focusScope: "all"   // "all" | "space"

  // Focus mode.
  property bool focusOn: false
  property double focusSince: 0
  property double focusEndsAt: 0
  property int focusMinutes: 0

  // Herdr.
  readonly property var emptyCounts: ({ working: 0, blocked: 0, done: 0, idle: 0, unknown: 0 })
  property var herd: ({ available: false, host: "", focusedSpace: null, windowAddress: null,
                        spaces: [], agents: [], counts: emptyCounts })
  property var events: []
  property int eventSeq: 0
  property int rev: 0
  property bool restored: false

  // Welcome back: when the Herdr window has been out of focus for a while.
  property double herdAwaySince: 0
  property var welcome: null          // { text, at }
  readonly property int welcomeAfterMs: 90 * 1000

  // Border state we applied to the Herdr window for blocked agents.
  property string blockedBorderAddress: ""

  readonly property string activeAddress: normaliseAddress(Hyprland.activeToplevel
    ? Hyprland.activeToplevel.address : "")
  readonly property bool herdWindowActive: !!herd.windowAddress
    && normaliseAddress(herd.windowAddress) === activeAddress

  signal juiceEvent(var event)

  function normaliseAddress(value) {
    var text = String(value || "").toLowerCase()
    return text.indexOf("0x") === 0 ? text.slice(2) : text
  }

  // ---------- state bus ----------

  function snapshot() {
    return {
      rev: rev,
      motion: motion,
      focus: {
        on: focusOn,
        since: focusOn ? focusSince : null,
        endsAt: focusOn && focusEndsAt > 0 ? focusEndsAt : null,
        minutes: focusOn && focusMinutes > 0 ? focusMinutes : null,
        held: 0,
        scope: focusScope
      },
      herd: herd,
      events: events
    }
  }

  function writeState() {
    rev += 1
    stateFile.setText(JSON.stringify(snapshot()))
  }

  function pushEvent(kind, data) {
    eventSeq += 1
    var event = { seq: eventSeq, kind: kind, at: Date.now(), data: data || {} }
    var next = events.slice(Math.max(0, events.length - 19))
    next.push(event)
    events = next
    juiceEvent(event)
    return event
  }

  function saveSettings() {
    settingsFile.setText(JSON.stringify({ motion: motion, focusScope: focusScope }))
  }

  function loadSettings(text) {
    try {
      var data = JSON.parse(text || "{}")
      if (data.motion === "reduced" || data.motion === "full") motion = data.motion
      if (data.focusScope === "space" || data.focusScope === "all") focusScope = data.focusScope
    } catch (e) {}
  }

  // A shell reload must not forget an active focus session.
  function restoreFromState(text) {
    if (restored) return
    restored = true
    try {
      var data = JSON.parse(text || "{}")
      var focus = data.focus || {}
      if (focus.on) {
        focusOn = true
        focusSince = Number(focus.since || Date.now())
        focusEndsAt = Number(focus.endsAt || 0)
        focusMinutes = Number(focus.minutes || 0)
        if (focusEndsAt > 0 && focusEndsAt <= Date.now()) focusOff()
      }
      if (Array.isArray(data.events)) {
        events = data.events.slice(-20)
        for (var i = 0; i < events.length; i++) eventSeq = Math.max(eventSeq, Number(events[i].seq || 0))
      }
    } catch (e) {}
    writeState()
  }

  // ---------- commands ----------

  function run(argv) {
    Quickshell.execDetached(argv)
  }

  function sound(name) {
    run([binDir + "/juice-sound", name])
  }

  function notify(urgency, summary, body, agent) {
    run(["notify-send", "-a", "Herdr", "-u", urgency,
         "-h", "string:x-herdr-pane:" + agent.pane,
         "-h", "string:x-herdr-space:" + agent.space,
         summary, body || ""])
  }

  // ---------- focus mode ----------

  function startFocus(minutes) {
    var mins = Math.max(0, Math.round(Number(minutes) || 0))
    var wasOn = focusOn
    focusMinutes = mins
    focusEndsAt = mins > 0 ? Date.now() + mins * 60000 : 0
    if (!wasOn) {
      focusOn = true
      focusSince = Date.now()
      run([binDir + "/juice-focus-apply", "on"])
      run(["omarchy-shell", "-q", "tyler.media", "startFocusStation"])
      sound("focus-on")
      pushEvent("focus-on", { minutes: mins })
    }
    writeState()
  }

  // `timer`: the focus timer ran out, which has its own sound.
  function focusOff(reason) {
    if (!focusOn) return
    focusOn = false
    focusSince = 0
    focusEndsAt = 0
    focusMinutes = 0
    run([binDir + "/juice-focus-apply", "off"])
    sound(reason === "timer" ? "timer-end" : "focus-off")
    pushEvent("focus-off", reason === "timer" ? { timer: true } : {})
    writeState()
  }

  function focusToggle() {
    if (focusOn) focusOff()
    else startFocus(0)
  }

  function cycleFocusScope() {
    focusScope = focusScope === "all" ? "space" : "all"
    saveSettings()
    writeState()
  }

  function setMotion(value) {
    motion = value === "reduced" ? "reduced" : "full"
    saveSettings()
    writeState()
  }

  function herdFocus(pane) {
    if (!pane) return
    run(["herdr", "agent", "focus", String(pane)])
    if (validAddress(herd.windowAddress))
      run(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:' + herd.windowAddress + '" })'])
  }

  // ---------- Herdr ----------

  // Tyler is looking at an agent when the Herdr window is focused on its space.
  function isWatched(agent) {
    return herdWindowActive && agent.space === herd.focusedSpace
  }

  // Blocked agents reach Tyler everywhere except outside the current space
  // when focus is narrowed to it.
  function blockedGetsThrough(agent) {
    return !(focusOn && focusScope === "space" && agent.space !== herd.focusedSpace)
  }

  function onAgentBlocked(agent) {
    pushEvent("agent-blocked", { pane: agent.pane, space: agent.space, title: agent.title })
    if (isWatched(agent) || !blockedGetsThrough(agent)) return
    sound("blocked")
    notify("critical", agent.space + " needs you", agent.title, agent)
  }

  function onAgentDone(agent) {
    pushEvent("agent-done", { pane: agent.pane, space: agent.space, title: agent.title })
    if (isWatched(agent) || focusOn) return false
    notify("normal", agent.space + " finished", agent.title, agent)
    return true
  }

  function consumeHerd(line) {
    var next
    try { next = JSON.parse(line) } catch (e) { return }
    if (!next || typeof next !== "object") return
    if (!next.counts) next.counts = emptyCounts
    if (!Array.isArray(next.agents)) next.agents = []

    var previous = {}
    for (var i = 0; i < herd.agents.length; i++) previous[herd.agents[i].pane] = herd.agents[i].status
    var hadHerd = herd.available

    herd = next

    if (hadHerd) {
      var announcedDone = false
      for (var j = 0; j < next.agents.length; j++) {
        var agent = next.agents[j]
        var before = previous[agent.pane]
        if (before === agent.status) continue
        if (agent.status === "blocked") onAgentBlocked(agent)
        else if (agent.status === "done" && before === "working") announcedDone = onAgentDone(agent) || announcedDone
        else if (agent.status === "working" && before !== undefined)
          pushEvent("agent-working", { pane: agent.pane, space: agent.space })
      }
      // The last one finishing settles the whole herd: one low note instead.
      var wasWorking = 0
      for (var p in previous) if (previous[p] === "working") wasWorking++
      var allQuiet = wasWorking > 0 && next.counts.working === 0 && next.counts.blocked === 0
      if (allQuiet && !herdWindowActive) sound("all-quiet")
      else if (announcedDone) sound("done")
    }
    syncBlockedBorder()
    writeState()
  }

  function colorArg(c) {
    function hex(v) { var h = Math.round(v * 255).toString(16); return h.length < 2 ? "0" + h : h }
    return "rgba(" + hex(c.r) + hex(c.g) + hex(c.b) + "ff)"
  }

  // The Herdr window's border takes the urgent role while any agent is blocked.
  function syncBlockedBorder() {
    var target = herd.counts && herd.counts.blocked > 0 && herd.windowAddress ? String(herd.windowAddress) : ""
    if (target === blockedBorderAddress) return
    if (blockedBorderAddress) {
      setWindowProp(blockedBorderAddress, "active_border_color", "unset")
      setWindowProp(blockedBorderAddress, "inactive_border_color", "unset")
    }
    if (target) {
      var urgent = colorArg(Color.urgent)
      setWindowProp(target, "active_border_color", urgent)
      setWindowProp(target, "inactive_border_color", urgent)
    }
    blockedBorderAddress = target
  }

  // Hyprland addresses come from hyprctl; only plain hex ever reaches Lua.
  function validAddress(address) {
    return /^0x[0-9a-fA-F]+$/.test(String(address || ""))
  }

  function setWindowProp(address, prop, value) {
    if (!validAddress(address)) return
    run(["hyprctl", "dispatch", 'hl.dsp.window.set_prop({ window = "address:' + address
      + '", prop = "' + prop + '", value = "' + value + '" })'])
  }

  function summariseAway(since) {
    var bySpace = {}
    var order = []
    for (var i = 0; i < events.length; i++) {
      var e = events[i]
      if (e.at < since) continue
      if (e.kind !== "agent-done" && e.kind !== "agent-blocked") continue
      var space = e.data.space || "agent"
      if (!(space in bySpace)) order.push(space)
      bySpace[space] = e.kind === "agent-blocked" ? "blocked" : (bySpace[space] === "blocked" ? "blocked" : "done")
    }
    // A space that was blocked but has moved on is no longer news.
    var parts = []
    for (var k = 0; k < order.length; k++) {
      var label = order[k]
      var live = null
      for (var a = 0; a < herd.agents.length; a++) if (herd.agents[a].space === label) live = herd.agents[a].status
      var state = bySpace[label]
      if (state === "blocked" && live !== "blocked") state = live === "done" ? "done" : ""
      if (state) parts.push(label + " " + state)
    }
    return parts.join(" · ")
  }

  onHerdWindowActiveChanged: {
    if (!herd.windowAddress) return
    if (!herdWindowActive) {
      herdAwaySince = Date.now()
      return
    }
    var since = herdAwaySince
    herdAwaySince = 0
    if (since <= 0 || Date.now() - since < welcomeAfterMs) return
    var text = summariseAway(since)
    if (!text) return
    welcome = { text: text, at: Date.now() }
    pushEvent("welcome-back", { text: text })
    writeState()
  }

  // ---------- plumbing ----------

  Component.onCompleted: {
    ServiceBridge.publish(root)
    Quickshell.execDetached(["mkdir", "-p", runtimeDir, settingsDir])
    startupTimer.start()
  }
  Component.onDestruction: ServiceBridge.clear(root)

  // Give mkdir a moment, then load settings and any focus session in flight.
  Timer {
    id: startupTimer
    interval: 150
    onTriggered: {
      settingsFile.reload()
      previousState.reload()
      bridge.running = true
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    preload: false
    onLoaded: root.loadSettings(text())
  }

  FileView {
    id: previousState
    path: root.statePath
    watchChanges: false
    printErrors: false
    preload: false
    onLoaded: root.restoreFromState(text())
    onLoadFailed: root.restoreFromState("{}")
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    preload: false
  }

  Process {
    id: bridge
    command: [root.binDir + "/juice-herd-bridge"]
    running: false
    stdout: SplitParser { onRead: function(line) { root.consumeHerd(line) } }
    onExited: bridgeRestart.start()
  }

  Timer {
    id: bridgeRestart
    interval: 3000
    onTriggered: bridge.running = true
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.focusOn && root.focusEndsAt > 0
    onTriggered: if (Date.now() >= root.focusEndsAt) root.focusOff("timer")
  }

  Sounds { service: root }

  IpcHandler {
    target: "tyler.juice"

    function status(): string { return JSON.stringify(root.snapshot()) }
    function focusToggle(): string { root.focusToggle(); return root.focusOn ? "on" : "off" }
    function focusOn(minutes: int): string { root.startFocus(minutes); return "on" }
    // Other juice plugins record moments on the bus: kind is one of the
    // contract's event kinds, data an optional JSON object.
    function event(kind: string, data: string): string {
      var allowed = ["screenshot", "theme-changed"]
      if (allowed.indexOf(kind) === -1) return "unknown kind"
      var payload = {}
      try { payload = data ? JSON.parse(data) : {} } catch (e) { payload = {} }
      root.pushEvent(kind, payload)
      root.writeState()
      return "ok"
    }
    function focusOff(): string { root.focusOff(); return "off" }
    function focusScope(scope: string): string {
      if (scope === "all" || scope === "space") { root.focusScope = scope; root.saveSettings(); root.writeState() }
      return root.focusScope
    }
    function herdFocus(pane: string): string { root.herdFocus(pane); return "ok" }
    function motion(value: string): string { root.setMotion(value); return root.motion }
  }
}
