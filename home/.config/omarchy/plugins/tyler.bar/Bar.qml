import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel
import "Attention.js" as Attention
import "widgets/KeyboardLayoutModel.js" as KeyboardLayoutModel
import "../tyler.juice/Motion.js" as Motion

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath
  property var barWidgetRegistry
  property var barConfig
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  property color foreground: themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: Color.bar.background
  property color urgent: Color.bar.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []

  // ------------------------------------------------------------------ juice
  //
  // Drawers (`bar.drawers`): one quiet mark per group; members fold away
  // inline and come back out while they are in trouble or have news. Modes
  // (`bar.modes` + the juice state bus): focus, meeting and away. Power-up:
  // widgets appear left to right once per login. See README "Juice".
  property var drawers: ({})
  property var drawerOfId: ({})
  property var modes: BarModel.normalizeModes(null)
  // Fold/unfold rhythm: the whole stagger across a drawer fits in this.
  readonly property int drawerRhythm: 150
  readonly property int powerUpSpan: 800
  readonly property string juiceRuntimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tyler-juice"
  property bool juiceRuntimeReady: false
  property var bus: ({})
  property bool busLoaded: false
  property var fake: Attention.parseFake("")
  property string fakeText: ""
  readonly property string motionMode: bus && bus.motion === "reduced" ? "reduced" : "full"
  readonly property bool reducedMotion: motionMode === "reduced"
  readonly property bool focusOn: fake.focus || !!(bus && bus.focus && bus.focus.on === true)
  // Meeting: a running calendar meeting, a live Meeting Recorder session, or
  // anything that publishes `meeting.on` on the state bus.
  property double meetingClock: Date.now()
  readonly property bool calendarMeeting: {
    var now = root.meetingClock
    var id = root.modes.meeting.calendar
    for (var i = 0; i < root.moduleSlots.length; i++) {
      var slot = root.moduleSlots[i]
      if (!slot || slot.moduleName !== id || !slot.activeItem) continue
      if (Attention.meetingNow(slot.activeItem.visibleEventList, now)) return true
    }
    return false
  }
  readonly property bool recorderMeeting: {
    var id = root.modes.meeting.recorder
    for (var i = 0; i < root.moduleSlots.length; i++) {
      var slot = root.moduleSlots[i]
      if (slot && slot.moduleName === id && slot.activeItem && slot.activeItem.recorderState === "recording") return true
    }
    return false
  }
  readonly property bool busMeeting: !!(bus && bus.meeting && bus.meeting.on === true)
  readonly property bool meetingOn: modes.meeting.enabled && (fake.meeting || busMeeting || calendarMeeting || recorderMeeting)
  readonly property bool awayOn: modes.away.enabled && (fake.away || awayMonitor.isIdle)
  property real awayLevel: awayOn ? 1 : 0
  Behavior on awayLevel {
    NumberAnimation { duration: Motion.duration(Motion.settle, root.motionMode); easing.type: Easing.InOutCubic }
  }
  readonly property real awayOpacity: 1 - awayLevel * (1 - modes.away.opacity)

  // ---- sounds the bar is first to know ----
  readonly property string juiceSoundBin: (Quickshell.env("HOME") || "") + "/.local/bin/juice-sound"
  function juiceSound(name) {
    Quickshell.execDetached([juiceSoundBin, name])
  }
  // juice-sound keeps quiet during a meeting, and meetings are known here.
  function syncMeetingFlag() {
    if (!juiceRuntimeReady) return
    Quickshell.execDetached(meetingOn ? ["touch", juiceRuntimeDir + "/meeting"] : ["rm", "-f", juiceRuntimeDir + "/meeting"])
  }
  onMeetingOnChanged: syncMeetingFlag()
  onJuiceRuntimeReadyChanged: syncMeetingFlag()
  onAwayOnChanged: if (!awayOn) juiceSound("welcome")
  // The day's first login gets a chord as the bar powers up.
  function loginChord() {
    var stamp = (Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "") + "/.local/state")) + "/tyler-juice/last-login-day"
    Quickshell.execDetached(["sh", "-c",
      "d=$(date +%F); [ \"$(cat \"$1\" 2>/dev/null)\" = \"$d\" ] && exit 0; "
      + "mkdir -p \"$(dirname \"$1\")\" && echo \"$d\" > \"$1\" && exec \"$2\" login",
      "sh", stamp, juiceSoundBin])
  }
  // Ibara: a sound when more starts waiting for Tyler, another when a task ends.
  readonly property var ibaraService: {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.moduleName === "io.zet.ibara" && slot.activeItem && slot.activeItem.ibaraService)
        return slot.activeItem.ibaraService
    }
    return null
  }
  readonly property int ibaraNeeds: ibaraService ? Number(ibaraService.needsYouCount || 0) : 0
  property int ibaraNeedsSeen: 0
  property bool ibaraSettled: false
  onIbaraServiceChanged: { ibaraSettled = false; ibaraSettle.restart() }
  onIbaraNeedsChanged: {
    if (ibaraSettled && ibaraNeeds > ibaraNeedsSeen) juiceSound("ibara-ask")
    ibaraNeedsSeen = ibaraNeeds
  }
  Timer {
    id: ibaraSettle
    // Ibara reports what was already waiting as it connects; that is not news.
    interval: 5000
    onTriggered: { root.ibaraNeedsSeen = root.ibaraNeeds; root.ibaraSettled = true }
  }
  Connections {
    target: root.ibaraService
    ignoreUnknownSignals: true
    function onTaskDone(computerId) { if (root.ibaraSettled) root.juiceSound("ibara-done") }
  }

  // "pending" keeps widgets hidden until the login marker has been checked,
  // "run" plays the power-up, "done" shows everything as it is created.
  property string powerUpPhase: "pending"
  property var keyboardState: ({ index: 0, keymap: "" })
  property string keyboardProbeName: ""
  property bool keyboardProbePending: false
  readonly property var attentionContext: ({ keyboard: root.keyboardState, trayNeedsAttention: Status.NeedsAttention })
  property int slotSerial: 0

  function drawerSpec(id) {
    return drawers[String(id || "")] || null
  }

  function drawerFor(id) {
    return drawerOfId[String(id || "")] || ""
  }

  function focusKeeps(id) {
    return id === centerAnchor || modes.focus.keep.indexOf(id) !== -1
  }

  function meetingPromotes(id) {
    return modes.meeting.promote.indexOf(id) !== -1
  }

  function fakeLevel(id) {
    return fake.levels[String(id || "")] || 0
  }

  function slotForItem(item) {
    for (var i = 0; i < moduleSlots.length; i++) {
      if (moduleSlots[i] && moduleSlots[i].activeItem === item) return moduleSlots[i]
    }
    return null
  }

  function readBus(text) {
    try {
      var data = JSON.parse(String(text || ""))
      if (!Util.isPlainObject(data)) return
      bus = data
      busLoaded = true
    } catch (e) {
      // Keep the last good state; the writer replaces the file atomically, so a
      // bad read is a hand edit or a partial copy and the next change fixes it.
    }
  }

  function readFake(text) {
    var value = String(text || "")
    if (value === fakeText) return
    fakeText = value
    fake = Attention.parseFake(value)
  }

  function resolvePowerUp(firstThisLogin) {
    if (powerUpPhase !== "pending" || powerUpStartTimer.running) return
    // Only now write the marker, so the read above can never see our own write.
    juiceRuntimeSetup.running = true
    if (!firstThisLogin || reducedMotion) {
      powerUpPhase = "done"
      return
    }
    powerUpStartTimer.start()
  }

  function probeKeyboard(namedKeyboard) {
    keyboardProbeName = String(namedKeyboard || "")
    if (keyboardProbe.running) keyboardProbePending = true
    else keyboardProbe.running = true
  }

  function readKeyboards(text) {
    var listed
    try {
      listed = JSON.parse(text || "{}").keyboards
    } catch (e) {
      return
    }
    if (!Array.isArray(listed)) return
    var typed = listed.filter(function(k) { return KeyboardLayoutModel.isTypedKeyboard(k.name) })
    var kb = KeyboardLayoutModel.selectKeyboard(typed, keyboardProbeName)
    var index = kb ? KeyboardLayoutModel.layoutIndex(kb) : 0
    var keymap = kb ? String(kb.active_keymap || "") : ""
    if (index !== keyboardState.index || keymap !== keyboardState.keymap)
      keyboardState = { index: index, keymap: keymap }
  }

  // How long `drawer <id> open` keeps a drawer out with no pointer on it.
  readonly property int drawerKeyboardDwell: 4000

  function commandDrawer(id, action) {
    var name = String(id || "")
    var verb = String(action || "toggle")
    if (!drawerSpec(name)) return { error: "no drawer named " + name }
    if (["open", "close", "toggle", "pin"].indexOf(verb) === -1) return { error: "action must be open, close, toggle or pin" }

    // The mark on the focused monitor's bar, else any bar showing one.
    var focused = focusedScreenName()
    var markSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot.moduleName !== name || !slot.isDrawerMark || !slot.hub) continue
      if (!markSlot || (focused && slotScreenName(slot) === focused)) markSlot = slot
    }
    if (!markSlot) return { error: "drawer " + name + " has no mark on any bar" }

    var hub = markSlot.hub
    if (verb === "toggle") verb = hub.isOpen(name) ? "close" : "open"
    if (verb === "open") hub.openFor(name, drawerKeyboardDwell)
    else if (verb === "close") hub.close(name)
    else hub.pin(name)
    return { drawer: name, screen: slotScreenName(markSlot), open: hub.isOpen(name), pinned: hub.isPinned(name) }
  }

  function juiceSnapshot() {
    var slots = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot) continue
      slots.push({
        id: slot.moduleName,
        screen: slotScreenName(slot),
        drawer: slot.isDrawerMark ? "(mark)" : slot.drawerName,
        attention: slot.attentionLevel,
        reason: slot.attentionReason,
        drawn: BarModel.isDrawnSlot(slot)
      })
    }
    return {
      motion: motionMode,
      focus: focusOn,
      meeting: meetingOn,
      meetingSources: { calendar: calendarMeeting, recorder: recorderMeeting, bus: busMeeting, fake: fake.meeting },
      away: awayOn,
      powerUp: powerUpPhase,
      keyboard: keyboardState,
      fake: fake,
      slots: slots
    }
  }

  // Once per login: the marker lives in XDG_RUNTIME_DIR, which logind clears
  // when the session ends, so a shell reload or restart never replays it.
  // Read synchronously so a reload has its answer before the first frame.
  FileView {
    path: root.juiceRuntimeDir + "/bar-powered-up"
    blockLoading: true
    printErrors: false
    onLoaded: root.resolvePowerUp(false)
    onLoadFailed: root.resolvePowerUp(true)
  }

  // Creates the runtime directory (so the watchers below have something to
  // watch) and the power-up marker. Paths travel as arguments, not as script.
  Process {
    id: juiceRuntimeSetup
    command: ["sh", "-c", "mkdir -p -- \"$1\" && { [ -e \"$2\" ] || : > \"$2\"; }", "sh",
      root.juiceRuntimeDir, root.juiceRuntimeDir + "/bar-powered-up"]
    onExited: root.juiceRuntimeReady = true
  }

  Timer {
    id: powerUpStartTimer
    // Let the widgets size themselves first so each one's place along the
    // bar, which sets its moment, is where it will actually sit.
    interval: 350
    onTriggered: {
      root.loginChord()
      if (root.reducedMotion) {
        root.powerUpPhase = "done"
        return
      }
      root.powerUpPhase = "run"
      powerUpDoneTimer.start()
    }
  }

  Timer {
    id: powerUpDoneTimer
    interval: root.powerUpSpan + 600
    onTriggered: root.powerUpPhase = "done"
  }

  // Belt and braces: never leave the bar blank if the marker read never answers.
  Timer {
    interval: 2000
    running: root.powerUpPhase === "pending"
    onTriggered: if (root.powerUpPhase === "pending" && !powerUpStartTimer.running) root.resolvePowerUp(false)
  }

  FileView {
    id: busView
    path: root.juiceRuntimeDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBus(text())
  }

  // Test hook: { "<widget id>": 0|1|2, "@meeting": true, "@focus": true,
  // "@away": true }. Read only while the file exists; delete it to go back.
  FileView {
    id: fakeView
    path: root.juiceRuntimeDir + "/fake-attention.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readFake(text())
    onLoadFailed: root.readFake("")
  }

  // A file watch cannot see a file appear, so watch the directory for the
  // state bus arriving after the bar and for the test hook being created.
  FileView {
    path: root.juiceRuntimeReady ? root.juiceRuntimeDir : ""
    watchChanges: true
    printErrors: false
    onFileChanged: {
      busView.reload()
      fakeView.reload()
    }
  }

  // Directory watches can go quiet after bursts of changes (see bar-off
  // below); a slow re-read keeps the test hook and a late bus honest.
  Timer {
    interval: 4000
    running: true
    repeat: true
    onTriggered: {
      if (!root.busLoaded) busView.reload()
      fakeView.reload()
    }
  }

  Timer {
    interval: 30000
    running: root.modes.meeting.enabled
    repeat: true
    onTriggered: root.meetingClock = Date.now()
  }

  IdleMonitor {
    id: awayMonitor
    enabled: root.modes.away.enabled
    timeout: Math.round(root.modes.away.minutes * 60)
    respectInhibitors: true
  }

  // The keyboard widget shows the active keymap's name but not whether it is
  // the first (default) layout; ask Hyprland each time that name changes.
  Process {
    id: keyboardProbe
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.readKeyboards(text)
    }
    onExited: {
      if (!root.keyboardProbePending) return
      root.keyboardProbePending = false
      keyboardProbe.running = true
    }
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    setRequestedTransparency(config.transparent === true)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")
    // Drawers and modes sit beside the layout, so they apply before the
    // settings-only shortcut below returns.
    drawers = BarModel.normalizeDrawers(config.drawers)
    drawerOfId = BarModel.drawerMembership(drawers)
    modes = BarModel.normalizeModes(config.modes)

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    // A member folded into its drawer (or hidden by focus) has no size to
    // anchor a panel on. Unfold it first, then open.
    var slot = slotForItem(item)
    if (slot && typeof slot.revealThenOpen === "function" && !BarModel.isDrawnSlot(slot)) {
      slot.revealThenOpen()
      return true
    }
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: applyBarConfig()

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.enabled !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function itemInside(item, ancestor) {
    for (var p = item; p; p = p.parent) if (p === ancestor) return true
    return false
  }

  function moduleClickTargetAt(slot, localX, localY) {
    // clickTargets is shared across every slot and bar surface, and hit
    // testing ignores clipping: a widget folded into a drawer keeps its full
    // size inside a zero-width slot, overlapping its neighbours. Only a
    // target inside the clicked slot may take the click (enabled is false
    // while folded), and the right/bottom edges stay exclusive.
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue
      if (!itemInside(target, slot)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x < target.width &&
          targetPoint.y >= 0 && targetPoint.y < target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }

    // Juice diagnostics for testing: modes, power-up and each slot's drawer
    // and attention. `omarchy-shell omarchy.bar juice`
    function juice(): string {
      return JSON.stringify(root.juiceSnapshot())
    }

    // Drive a drawer without a pointer (tests, keybindings). Acts on the
    // focused monitor's bar. open: unfolds, then folds again after the
    // keyboard dwell unless the pointer or a pin holds it. close: unpins and
    // folds. toggle: open or close. pin: pins it open.
    // `omarchy-shell omarchy.bar drawer tyler.systems toggle`
    function drawer(id: string, action: string): string {
      return JSON.stringify(root.commandDrawer(id, action))
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: root.barHidden && root.position === "top" ? -root.barSize : 0
      bottom: root.barHidden && root.position === "bottom" ? -root.barSize : 0
      left: root.barHidden && root.position === "left" ? -root.barSize : 0
      right: root.barHidden && root.position === "right" ? -root.barSize : 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize
    color: root.transparent ? "transparent"
      : Qt.rgba(root.background.r, root.background.g, root.background.b, root.background.a * root.awayOpacity)
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    // Per-surface drawer state: hovering one monitor's mark leaves the others be.
    DrawerHub { id: drawerHub }

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar
      // Away: the whole bar fades right down until the next input.
      opacity: root.awayOpacity

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: horizontalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent; hub: drawerHub }

        LeftModules {
          hub: drawerHub
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        RightModules {
          hub: drawerHub
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent; hub: drawerHub }

        LeftModules {
          hub: drawerHub
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          hub: drawerHub
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    property var hub: null
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          hub: centerRoot.hub
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          hub: centerRoot.hub
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          hub: centerRoot.hub
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          hub: centerRoot.hub
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          hub: centerRoot.hub
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          hub: centerRoot.hub
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          hub: centerRoot.hub
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          hub: centerRoot.hub
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""
    // The bar surface's DrawerHub, handed to every slot in the list.
    property var hub: null

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
            hub: moduleListRoot.hub
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
            hub: moduleListRoot.hub
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    // The bar surface's DrawerHub (null only for a slot built outside a bar).
    property var hub: null
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    // A layout entry whose id names a drawer in `bar.drawers` is that drawer's
    // mark, drawn by the engine rather than loaded from the registry.
    readonly property var drawerSpec: root.drawerSpec(moduleName)
    readonly property bool isDrawerMark: drawerSpec !== null
    // Engine-drawn widgets that need no plugin of their own.
    readonly property bool isScratchpad: moduleName === "tyler.scratchpad"
    readonly property bool engineDrawn: isDrawerMark || isScratchpad
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType || engineDrawn) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml" && !engineDrawn
    readonly property bool commandCustom: customType === "command" && !engineDrawn
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }

    // ---- juice: drawer membership, attention and modes ----
    property int serial: 0
    // Drawer and mode changes apply without animating until the slot has been
    // up for a moment: a reload must not replay every drawer folding shut.
    property bool settled: false
    readonly property string drawerName: isDrawerMark ? "" : root.drawerFor(moduleName)
    readonly property string hubKey: isDrawerMark ? "mark:" + moduleName : (drawerName ? "member:" + drawerName : "")
    property string registeredHubKey: ""
    property var registeredHub: null
    readonly property int layoutIndex: root.entryIndex(root.layoutEntries(region), moduleName)
    readonly property var attention: isDrawerMark ? ({ level: 0, reason: "" })
      : Attention.evaluate(moduleName, activeItem, root.attentionContext)
    readonly property int attentionRaw: Math.max(attention.level, root.fakeLevel(moduleName))
    // Settled attention. A rise waits out a short debounce so a service still
    // starting up (no network device yet, no default sink yet) never flashes
    // trouble; a fall applies at once.
    property int attentionLevel: 0
    readonly property string attentionReason: attention.reason !== "" ? attention.reason
      : (root.fakeLevel(moduleName) > 0 ? "Test hook (fake-attention.json)" : "")
    readonly property bool meetingPromoted: root.meetingOn && root.meetingPromotes(moduleName)
    // Summoned by hotkey or IPC while folded away: unfold, then open.
    property bool summoned: false
    readonly property bool held: panelOpen || summoned || dragSource
    readonly property bool drawerLive: drawerName !== "" && !!hub && hub.hasMark(drawerName)
    readonly property bool drawerShown: {
      if (isDrawerMark) return !!hub && hub.memberSlots(moduleName).length > 0
      if (!drawerLive) return true
      return held || attentionLevel > 0 || meetingPromoted || hub.isOpen(drawerName)
    }
    readonly property bool modeShown: {
      if (!root.focusOn) return true
      if (isDrawerMark) return false
      return held || attentionLevel > 0 || meetingPromoted || root.focusKeeps(moduleName)
    }
    // Hovering (or holding a panel open from) a mark or a shown member keeps
    // an already open drawer open; letting go starts the hub's grace delay.
    // Hover never opens one: only a click on the mark (or IPC) does, so a
    // pointer passing along the bar leaves the layout where it is.
    readonly property bool holdsDrawer: hubKey !== "" && !!hub && hub.isOpen(hubName())
      && (moduleHover.hovered || panelOpen || summoned)
    property real drawerExtent: 1
    property real drawerFade: 1
    property real modeLevel: 1
    property real powerLevel: root.powerUpPhase === "done" ? 1 : 0
    readonly property real axisFactor: drawerExtent * modeLevel
    readonly property real fullWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    readonly property real fullHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0

    // Folding runs along the bar: widths on a horizontal bar, heights on a
    // vertical one.
    implicitWidth: root.vertical ? fullWidth : Math.round(fullWidth * axisFactor)
    implicitHeight: root.vertical ? Math.round(fullHeight * axisFactor) : fullHeight
    width: implicitWidth
    height: implicitHeight
    clip: axisFactor < 1
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: {
      root.slotSerial += 1
      serial = root.slotSerial
      root.registerModuleSlot(slot)
      syncHub()
      drawerExtent = drawerShown ? 1 : 0
      drawerFade = drawerExtent
      modeLevel = modeShown ? 1 : 0
      if (root.powerUpPhase === "run") startPowerUp()
    }
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
      releaseHub()
    }

    onHubKeyChanged: syncHub()
    onHubChanged: syncHub()
    onHoldsDrawerChanged: if (registeredHub) registeredHub.setHold(hubName(), "s" + serial, holdsDrawer)
    onDrawerShownChanged: applyDrawer()
    onModeShownChanged: applyMode()
    onAttentionRawChanged: settleAttention()
    onPanelOpenChanged: if (!panelOpen && summoned && !revealOpenTimer.running) summoned = false

    function hubName() {
      return isDrawerMark ? moduleName : drawerName
    }

    function releaseHub() {
      var old = registeredHub
      var key = registeredHubKey
      registeredHub = null
      registeredHubKey = ""
      if (!old || !key) return
      try {
        var name = key.substring(key.indexOf(":") + 1)
        old.setHold(name, "s" + serial, false)
        if (key.indexOf("mark:") === 0) old.unregisterMark(name, slot)
        else old.unregisterMember(name, slot)
      } catch (e) {
        // The hub went down with its bar surface first.
      }
    }

    function syncHub() {
      if (serial === 0) return
      if (registeredHub === hub && registeredHubKey === hubKey) return
      releaseHub()
      if (!hub || !hubKey) return
      registeredHub = hub
      registeredHubKey = hubKey
      if (isDrawerMark) hub.registerMark(moduleName, slot)
      else hub.registerMember(drawerName, slot)
      if (holdsDrawer) hub.setHold(hubName(), "s" + serial, true)
    }

    function settleAttention() {
      if (attentionRaw <= attentionLevel) {
        attentionTimer.stop()
        attentionLevel = attentionRaw
      } else if (!attentionTimer.running) {
        attentionTimer.start()
      }
    }

    function applyDrawer() {
      var target = drawerShown ? 1 : 0
      drawerAnim.stop()
      if (!settled || root.reducedMotion) {
        drawerExtent = target
        drawerFade = target
        return
      }
      if (drawerExtent === target && drawerFade === target) return
      extentAnim.to = target
      extentAnim.easing.type = target ? Easing.OutCubic : Easing.InOutCubic
      fadePause.duration = target && hub && drawerName ? hub.staggerDelay(drawerName, slot) : 0
      fadeAnim.to = target
      fadeAnim.duration = target ? Motion.drawer : Motion.ack
      drawerAnim.start()
    }

    function applyMode() {
      var target = modeShown ? 1 : 0
      modeAnim.stop()
      if (!settled || root.reducedMotion) {
        modeLevel = target
        return
      }
      modeAnim.to = target
      modeAnim.start()
    }

    // Power-up: each widget's moment is its place along the bar, so the bar
    // fills left to right (top to bottom when vertical).
    function startPowerUp() {
      if (root.powerUpPhase !== "run" || root.reducedMotion) {
        powerAnim.stop()
        powerLevel = 1
        return
      }
      var fraction = 0
      try {
        var point = slot.mapToItem(null, 0, 0)
        var window = root.slotWindow(slot)
        var span = window ? (root.vertical ? window.height : window.width) : 0
        if (span > 0) fraction = Util.clamp((root.vertical ? point.y : point.x) / span, 0, 1)
      } catch (e) {
      }
      powerLevel = 0
      powerPause.duration = Math.round(fraction * root.powerUpSpan)
      powerAnim.restart()
    }

    function revealThenOpen() {
      summoned = true
      revealOpenTimer.interval = root.reducedMotion ? 0 : Math.max(Motion.drawer, Motion.settle) + 40
      revealOpenTimer.restart()
    }

    Connections {
      target: root
      function onPowerUpPhaseChanged() {
        if (root.powerUpPhase === "run") slot.startPowerUp()
        else if (root.powerUpPhase === "done" && !powerAnim.running) slot.powerLevel = 1
      }
    }

    // Keyboard layout: the widget names the active keymap; whether that is
    // the default layout comes from asking Hyprland each time the name moves.
    Connections {
      target: slot.moduleName === "omarchy.keyboard-layout" ? slot.activeItem : null
      ignoreUnknownSignals: true
      function onLayoutFullChanged() {
        root.probeKeyboard(slot.activeItem ? slot.activeItem.typedKeyboardName : "")
      }
    }

    Timer {
      interval: 400
      running: true
      onTriggered: slot.settled = true
    }

    Timer {
      id: attentionTimer
      interval: 1500
      onTriggered: slot.attentionLevel = slot.attentionRaw
    }

    Timer {
      id: revealOpenTimer
      onTriggered: {
        if (slot.activeItem && typeof slot.activeItem.open === "function") slot.activeItem.open()
        summonReleaseTimer.restart()
      }
    }

    // If the panel never took (or has closed again), stop holding the member
    // out of its drawer.
    Timer {
      id: summonReleaseTimer
      interval: 800
      onTriggered: if (!slot.panelOpen) slot.summoned = false
    }

    ParallelAnimation {
      id: drawerAnim
      NumberAnimation { id: extentAnim; target: slot; property: "drawerExtent"; duration: Motion.drawer }
      SequentialAnimation {
        PauseAnimation { id: fadePause; duration: 0 }
        NumberAnimation { id: fadeAnim; target: slot; property: "drawerFade"; easing.type: Easing.OutCubic }
      }
    }

    NumberAnimation {
      id: modeAnim
      target: slot
      property: "modeLevel"
      duration: Motion.settle
      easing.type: Easing.InOutCubic
    }

    SequentialAnimation {
      id: powerAnim
      PauseAnimation { id: powerPause; duration: 0 }
      NumberAnimation { target: slot; property: "powerLevel"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    // The widget keeps its full size while the slot around it folds, so it
    // never re-lays itself out mid-animation; the slot clips it instead. It
    // stays loaded (and live) while folded, and takes no input.
    Item {
      id: slotBody
      width: slot.fullWidth
      height: slot.fullHeight
      opacity: slot.drawerFade * slot.modeLevel * slot.powerLevel
      enabled: slot.drawerShown && slot.modeShown
      transform: Translate {
        // A small rise into place during the power-up.
        x: root.vertical ? (1 - slot.powerLevel) * Style.space(3) * (root.position === "left" ? -1 : 1) : 0
        y: root.vertical ? 0 : (1 - slot.powerLevel) * Style.space(3) * (root.position === "bottom" ? 1 : -1)
      }

      Loader {
        id: componentLoader
        active: !slot.qmlCustom && !slot.registered
        sourceComponent: slot.commandCustom ? customCommandModuleComponent
          : (slot.isDrawerMark ? drawerMarkComponent
            : (slot.isScratchpad ? scratchpadComponent : emptyModuleComponent))
        anchors.fill: parent
        opacity: slot.dragSource ? 0.22 : 1.0
        onLoaded: {
          slot.injectProps()
          Qt.callLater(slot.injectProps)
        }
      }

      Loader {
        id: registryLoader
        active: slot.registered
        sourceComponent: slot.registered ? slot.registryComponent : null
        anchors.fill: parent
        opacity: slot.dragSource ? 0.22 : 1.0
        onLoaded: {
          slot.injectProps()
          Qt.callLater(slot.injectProps)
        }
      }

      Loader {
        id: qmlLoader
        active: slot.qmlCustom
        source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
        anchors.fill: parent
        opacity: slot.dragSource ? 0.22 : 1.0
        onLoaded: {
          slot.injectProps()
          Qt.callLater(slot.injectProps)
        }
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }

    Component {
      id: drawerMarkComponent
      DrawerMark { host: slot }
    }

    Component {
      id: scratchpadComponent
      ScratchpadIndicator { }
    }
  }

  // One per bar surface. Tracks each drawer's mark and members on that
  // surface, what is holding it open (hover, an open panel, a pin), and the
  // grace delay after the pointer leaves. Maps are mutated in place and
  // announced through `rev`, which every reader touches.
  component DrawerHub: Item {
    id: hub

    readonly property int grace: 500
    property int rev: 0
    property var marks: ({})
    property var members: ({})
    property var holds: ({})
    property var pinned: ({})
    property var lingerUntil: ({})

    visible: false

    function touch() {
      rev = rev + 1
    }

    function hasMark(name) {
      var revision = hub.rev
      return !!marks[name]
    }

    function markSlot(name) {
      var revision = hub.rev
      return marks[name] || null
    }

    function memberSlots(name) {
      var revision = hub.rev
      return members[name] || []
    }

    function registerMark(name, slot) {
      marks[name] = slot
      touch()
    }

    function unregisterMark(name, slot) {
      if (marks[name] !== slot) return
      delete marks[name]
      delete pinned[name]
      touch()
    }

    function registerMember(name, slot) {
      var next = (members[name] || []).filter(function(s) { return s !== slot })
      next.push(slot)
      members[name] = next
      touch()
    }

    function unregisterMember(name, slot) {
      if (!members[name]) return
      members[name] = members[name].filter(function(s) { return s !== slot })
      touch()
    }

    function setHold(name, key, on) {
      if (!name || !key) return
      var set = holds[name] || ({})
      var had = Object.keys(set).length > 0
      if (on) {
        if (set[key] && lingerUntil[name] === undefined) return
        set[key] = true
        delete lingerUntil[name]
      } else {
        if (!set[key]) return
        delete set[key]
        if (had && Object.keys(set).length === 0) {
          lingerUntil[name] = Date.now() + grace
          lingerTimer.start()
        }
      }
      holds[name] = set
      touch()
    }

    function isPinned(name) {
      var revision = hub.rev
      return pinned[name] === true
    }

    // Open without a pointer: held for `ms`, then the usual fold. Only one
    // drawer is out at a time, so two never stack up into the centre.
    function openFor(name, ms) {
      closeOthers(name)
      lingerUntil[name] = Date.now() + Math.max(grace, ms)
      lingerTimer.start()
      touch()
    }

    // The mark's click: open and stay open (a member's own popup panel takes
    // the pointer off the bar, so folding on leave would pull the member out
    // from under it), or close.
    function toggle(name) {
      if (isOpen(name)) close(name)
      else pin(name)
    }

    function closeOthers(name) {
      for (var other in marks)
        if (other !== name) close(other)
    }

    function close(name) {
      delete pinned[name]
      delete lingerUntil[name]
      delete holds[name]
      touch()
    }

    function pin(name) {
      closeOthers(name)
      pinned[name] = true
      touch()
    }

    function isOpen(name) {
      var revision = hub.rev
      // A reorder drag opens every drawer so folded members can be drop targets.
      if (root.barDragSource) return true
      return pinned[name] === true
        || Object.keys(holds[name] || {}).length > 0
        || lingerUntil[name] !== undefined
    }

    // Unfolding fades members in one after another, nearest the mark first,
    // with the whole run fitting into root.drawerRhythm.
    function staggerDelay(name, slot) {
      var mark = marks[name]
      var list = (members[name] || []).filter(function(s) {
        return s && s.activeItem && s.activeItem.visible === true
      })
      if (!mark || list.length < 2) return 0
      function distance(s) {
        return s.region === mark.region ? Math.abs(s.layoutIndex - mark.layoutIndex) : 1000 + s.layoutIndex
      }
      list.sort(function(a, b) { return distance(a) - distance(b) })
      var rank = list.indexOf(slot)
      if (rank <= 0) return 0
      var step = Math.min(Motion.stagger, root.drawerRhythm / (list.length - 1))
      return Math.round(rank * step)
    }

    Timer {
      id: lingerTimer
      interval: 40
      repeat: true
      onTriggered: {
        var now = Date.now()
        var changed = false
        var left = 0
        for (var name in hub.lingerUntil) {
          if (hub.lingerUntil[name] <= now) {
            delete hub.lingerUntil[name]
            changed = true
          } else {
            left++
          }
        }
        if (left === 0) stop()
        if (changed) hub.touch()
      }
    }
  }

  // A drawer's one quiet mark: a dot (systems) or three small dots
  // (launchers). Muted at rest; accent when a member needs a look or has news,
  // urgent when one is broken or blocked; bar foreground while open or pinned.
  // Click opens the drawer and it stays open; click again folds it.
  component DrawerMark: Item {
    id: mark

    property var host: null
    readonly property string name: host ? host.moduleName : ""
    readonly property var spec: host ? host.drawerSpec : null
    readonly property var hub: host ? host.hub : null
    readonly property var memberList: hub ? hub.memberSlots(name) : []
    readonly property int level: {
      var best = 0
      for (var i = 0; i < memberList.length; i++) {
        var member = memberList[i]
        if (member && member.attentionLevel > best) best = member.attentionLevel
      }
      return best
    }
    readonly property string troubleText: {
      var lines = []
      for (var i = 0; i < memberList.length; i++) {
        var member = memberList[i]
        if (member && member.attentionLevel > 0 && member.attentionReason) lines.push(member.attentionReason)
      }
      if (lines.length === 0) return ""
      var label = spec && spec.label ? spec.label + ": " : ""
      return label + lines.join(" · ")
    }
    readonly property bool open: hub ? hub.isOpen(name) : false
    readonly property bool pinned: hub ? hub.isPinned(name) : false
    readonly property bool tooltipHovered: markHover.hovered
    readonly property color restInk: root.transparent ? root.barForeground : Color.muted
    // Not readonly: it carries a colour Behavior.
    property color ink: level >= 2 ? Color.urgent
      : level === 1 ? Color.accent
      : (open ? root.barForeground : restInk)
    // On a transparent bar the text colour is picked against the wallpaper,
    // so "muted" there is that colour, quietened.
    readonly property real inkOpacity: level > 0 || open ? 1 : (root.transparent ? 0.5 : 1)
    property real pulseScale: 1
    property int lastLevel: 0

    implicitWidth: root.vertical ? root.barSize : Style.space(16)
    implicitHeight: root.vertical ? Style.space(16) : root.barSize

    function triggerPress(button) {
      if (hub) hub.toggle(name)
    }

    onLevelChanged: {
      // One slow pulse when something new goes wrong; never a loop.
      if (level > lastLevel && !root.reducedMotion && host && host.settled) pulse.restart()
      lastLevel = level
    }
    onTroubleTextChanged: if (markHover.hovered) syncTooltip()

    function syncTooltip() {
      if (markHover.hovered && troubleText !== "") root.showTooltip(mark, troubleText)
      else root.hideTooltip(mark)
    }

    HoverHandler {
      id: markHover
      onHoveredChanged: mark.syncTooltip()
    }

    Behavior on ink {
      ColorAnimation { duration: Motion.duration(Motion.settle, root.motionMode); easing.type: Easing.InOutCubic }
    }

    SequentialAnimation {
      id: pulse
      NumberAnimation { target: mark; property: "pulseScale"; to: 1.7; duration: Motion.pulse * 0.35; easing.type: Easing.OutCubic }
      NumberAnimation { target: mark; property: "pulseScale"; to: 1; duration: Motion.pulse * 0.65; easing.type: Easing.InOutCubic }
    }

    Grid {
      anchors.centerIn: parent
      columns: root.vertical ? 1 : 3
      spacing: Style.space(2)
      opacity: mark.inkOpacity
      scale: mark.pulseScale

      Repeater {
        model: mark.spec && mark.spec.mark === "dots" ? 3 : 1

        Rectangle {
          readonly property int size: mark.spec && mark.spec.mark === "dots"
            ? Style.space(3)
            : (mark.level > 0 || mark.pinned ? Style.space(7) : Style.space(5))
          width: size
          height: size
          radius: size / 2
          color: mark.ink
        }
      }
    }
  }

  // Trouble-only: an app parked on special:scratchpad that wants attention.
  // Shows that app's icon, flattened to `urgent`, and nothing otherwise. It
  // reports itself through the generic `juiceAttention` contract, so focus
  // mode keeps it too. Click shows the scratchpad.
  component ScratchpadIndicator: Item {
    id: pad

    readonly property var workspace: {
      var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
      for (var i = 0; i < list.length; i++)
        if (list[i] && list[i].name === "special:scratchpad") return list[i]
      return null
    }
    readonly property var urgentWindow: {
      if (!workspace || !workspace.toplevels) return null
      var windows = workspace.toplevels.values || []
      for (var i = 0; i < windows.length; i++)
        if (windows[i] && windows[i].urgent === true) return windows[i]
      return workspace.urgent === true && windows.length > 0 ? windows[0] : null
    }
    // The test hook can light it with `"tyler.scratchpad": 2`.
    readonly property bool faked: root.fakeLevel("tyler.scratchpad") > 0
    readonly property bool wanting: urgentWindow !== null || faked
    readonly property string appClass: {
      var ipc = urgentWindow ? urgentWindow.lastIpcObject : null
      return ipc && ipc.class ? String(ipc.class) : ""
    }
    readonly property string appTitle: urgentWindow ? String(urgentWindow.title || appClass || "Scratchpad") : "Scratchpad (test)"
    readonly property string iconSource: {
      if (!appClass) return ""
      var entry = DesktopEntries.heuristicLookup(appClass)
      return Quickshell.iconPath(entry && entry.icon ? entry.icon : appClass.toLowerCase(), true)
    }
    readonly property int juiceAttention: wanting ? 2 : 0
    readonly property string juiceAttentionReason: wanting ? appTitle + " wants you (scratchpad)" : ""
    readonly property bool tooltipHovered: padHover.hovered

    visible: wanting
    implicitWidth: root.vertical ? root.barSize : Style.bar.iconSlot
    implicitHeight: root.vertical ? Style.bar.iconSlot : root.barSize

    function triggerPress(button) {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"scratchpad\")"])
    }

    HoverHandler {
      id: padHover
      onHoveredChanged: {
        if (hovered) root.showTooltip(pad, pad.juiceAttentionReason)
        else root.hideTooltip(pad)
      }
    }

    Image {
      id: padIcon
      anchors.centerIn: parent
      width: Style.space(14)
      height: width
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      source: pad.iconSource
      visible: false
      asynchronous: true
    }

    MultiEffect {
      anchors.fill: padIcon
      source: padIcon
      visible: padIcon.status === Image.Ready
      colorization: 1.0
      colorizationColor: Color.urgent
    }

    // No icon to be found: a plain urgent tile in its place.
    Rectangle {
      anchors.centerIn: parent
      visible: padIcon.status !== Image.Ready
      width: Style.space(10)
      height: width
      radius: Style.space(2)
      color: Color.urgent
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
