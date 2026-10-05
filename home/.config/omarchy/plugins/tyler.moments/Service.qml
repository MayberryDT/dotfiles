import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../tyler.juice/Motion.js" as Motion

// Desktop moments: short, single-shot overlays that mark something that just
// happened. Nothing here loops or stays on screen at rest.
//
//  - Theme sweep: one soft band crosses every monitor left to right in the new
//    theme's accent when the palette changes. It fires on the shell's own
//    palette swap (in step with Omarchy's wallpaper reveal) and on
//    `flash theme` from the theme-set hook; one theme change plays once.
//  - Screenshot: a faint edge flash in `foreground` on the captured monitor,
//    then a thumbnail that rises toward the notification chip. Clicking it
//    hands the file to `juice-herdr-screenshot` (send to the focused agent).
//
// IPC (`omarchy-shell tyler.moments <method>`):
//   flash <screenshot|theme>        flash the focused monitor / play the sweep
//   screenshot <path|-> <monitor>   flash that monitor and show the thumbnail
//   status                          small JSON state, for checks
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // Motion: the juice state bus says whether movement is reduced. Colour and
  // opacity keep their meaning either way; only travel is dropped.
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  property string motion: "full"
  readonly property bool reduced: motion === "reduced"

  // Durations from the brief: the sweep is a moment (~700 ms), the flash an
  // acknowledgement (~250 ms). Everything else uses the shared tokens.
  readonly property int sweepMs: 700
  readonly property int flashInMs: 60
  readonly property int flashOutMs: 190
  readonly property int shotHoldMs: 4200

  // ---- theme sweep ------------------------------------------------------
  property bool sweepActive: false
  property real sweepProgress: 0
  property real washOpacity: 0
  property double lastSweepAt: 0
  property string lastSweepPalette: ""
  // Colours load asynchronously at shell start; only palette changes after
  // that are theme switches.
  property bool paletteArmed: false

  readonly property string paletteSignature: String(Color.accent) + String(Color.foreground) + String(Color.background)

  // Horizontal extent of the whole desktop, so one band travels across every
  // monitor in turn instead of each monitor running its own.
  readonly property var desktopSpan: {
    var list = Quickshell.screens
    var min = 0, max = 0, seen = false
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (!s) continue
      if (!seen) { min = s.x; max = s.x + s.width; seen = true; continue }
      min = Math.min(min, s.x)
      max = Math.max(max, s.x + s.width)
    }
    return { min: min, max: seen ? max : 1920 }
  }

  function playTheme(fromHook) {
    var now = Date.now()
    // A theme change reaches us twice: the shell's palette swap, then the
    // theme-set hook a few seconds later. Same palette within the window means
    // the moment already played.
    if (fromHook && root.lastSweepPalette === root.paletteSignature && now - root.lastSweepAt < 30000)
      return "skipped"
    root.lastSweepAt = now
    root.lastSweepPalette = root.paletteSignature
    Util.execArgv(["juice-sound", "theme"])
    // Tell the state bus. Constant script: the theme name is read from
    // Omarchy's own state file and only reaches jq as an --arg.
    Util.execDetached("theme=$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null); "
      + "omarchy-shell -q tyler.juice event theme-changed \"$(jq -cn --arg theme \"$theme\" '{theme: $theme}')\"")
    sweepAnim.stop()
    washAnim.stop()
    root.sweepProgress = 0
    root.washOpacity = 0
    root.sweepActive = true
    if (root.reduced) washAnim.start()
    else sweepAnim.start()
    return "ok"
  }

  Timer {
    id: armTimer
    interval: 5000
    running: true
    onTriggered: root.paletteArmed = true
  }

  // Color sets foreground, background and accent one after another; collapse
  // them into one change.
  Timer {
    id: paletteSettle
    interval: 40
    onTriggered: if (root.paletteArmed) root.playTheme(false)
  }

  Connections {
    target: Color
    function onAccentChanged() { paletteSettle.restart() }
    function onForegroundChanged() { paletteSettle.restart() }
    function onBackgroundChanged() { paletteSettle.restart() }
  }

  NumberAnimation {
    id: sweepAnim
    target: root
    property: "sweepProgress"
    from: 0
    to: 1
    duration: root.sweepMs
    easing.type: Easing.InOutCubic
    onFinished: root.sweepActive = false
  }

  // Reduced motion: no travel, one faint accent wash that comes and goes.
  SequentialAnimation {
    id: washAnim
    NumberAnimation { target: root; property: "washOpacity"; from: 0; to: 1; duration: Motion.ack; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "washOpacity"; to: 0; duration: Motion.settle; easing.type: Easing.InOutCubic }
    ScriptAction { script: root.sweepActive = false }
  }

  // ---- screenshot flash -------------------------------------------------
  property bool flashActive: false
  property string flashScreen: ""
  property real flashOpacity: 0

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function screenNameFor(requested) {
    var name = String(requested || "")
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++)
      if (list[i] && String(list[i].name) === name) return name
    var focused = root.focusedScreenName()
    if (focused) return focused
    return list.length > 0 && list[0] ? String(list[0].name) : ""
  }

  function playFlash(screenName) {
    root.flashScreen = root.screenNameFor(screenName)
    flashAnim.stop()
    root.flashOpacity = 0
    root.flashActive = true
    flashAnim.start()
  }

  SequentialAnimation {
    id: flashAnim
    NumberAnimation { target: root; property: "flashOpacity"; from: 0; to: 1; duration: root.flashInMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "flashOpacity"; to: 0; duration: root.flashOutMs; easing.type: Easing.InOutCubic }
    ScriptAction { script: root.flashActive = false }
  }

  // ---- screenshot thumbnail ---------------------------------------------
  property bool shotVisible: false
  property string shotPath: ""
  property string shotScreen: ""
  property real shotEnter: 0
  property real shotLeave: 0
  property bool shotLeaving: false
  property bool shotHovered: false
  // "" (idle) | "sending" | "sent" | "failed"
  property string shotResult: ""

  function validShotPath(path) {
    var p = String(path || "")
    if (p.length < 2 || p.length > 4096 || p.charAt(0) !== "/") return false
    if (p.indexOf("\n") !== -1 || p.indexOf("\u0000") !== -1) return false
    return /\.(png|jpe?g|webp)$/i.test(p)
  }

  function showShot(path, screenName) {
    shotEnterAnim.stop()
    shotLeaveAnim.stop()
    shotHold.stop()
    root.shotPath = path
    root.shotScreen = root.screenNameFor(screenName)
    root.shotResult = ""
    root.shotLeaving = false
    root.shotLeave = 0
    root.shotEnter = 0
    root.shotVisible = true
    shotEnterAnim.start()
  }

  function leaveShot() {
    if (!root.shotVisible || root.shotLeaving) return
    shotHold.stop()
    root.shotLeaving = true
    shotLeaveAnim.start()
  }

  function clearShot() {
    root.shotVisible = false
    root.shotLeaving = false
    root.shotPath = ""
    root.shotResult = ""
    root.shotEnter = 0
    root.shotLeave = 0
  }

  function sendShot() {
    if (!root.shotVisible || root.shotLeaving || root.shotResult !== "" || sendProc.running) return
    shotHold.stop()
    root.shotResult = "sending"
    sendProc.forPath = root.shotPath
    // Login shell for the session PATH; the path only ever lands in "$@".
    sendProc.command = ["bash", "-lc", "exec \"$@\"", "bash", "juice-herdr-screenshot", root.shotPath]
    sendProc.running = true
  }

  function finishSend(path, ok) {
    if (path !== root.shotPath || !root.shotVisible) return
    root.shotResult = ok ? "sent" : "failed"
    shotHold.interval = ok ? Motion.longFade : Motion.pulse * 2
    shotHold.restart()
  }

  Process {
    id: sendProc
    property string forPath: ""
    onExited: function(exitCode, exitStatus) { root.finishSend(sendProc.forPath, exitCode === 0) }
  }

  NumberAnimation {
    id: shotEnterAnim
    target: root
    property: "shotEnter"
    from: 0
    to: 1
    duration: Motion.duration(Motion.drawer, root.motion)
    easing.type: Easing.OutCubic
    onFinished: {
      shotHold.interval = root.shotHoldMs
      if (!root.shotHovered) shotHold.restart()
    }
  }

  NumberAnimation {
    id: shotLeaveAnim
    target: root
    property: "shotLeave"
    from: 0
    to: 1
    // Reduced motion keeps the fade (it carries "gone to the inbox") but
    // drops the travel, so a shorter fade is enough.
    duration: root.reduced ? Motion.settle : Math.round(Motion.settle * 1.5)
    easing.type: Easing.InOutCubic
    onFinished: root.clearShot()
  }

  Timer {
    id: shotHold
    interval: root.shotHoldMs
    onTriggered: root.leaveShot()
  }

  onShotHoveredChanged: {
    if (!root.shotVisible || root.shotLeaving || root.shotResult !== "") return
    if (root.shotHovered) shotHold.stop()
    else {
      shotHold.interval = Motion.pulse
      shotHold.restart()
    }
  }

  // ---- state bus ----------------------------------------------------------
  FileView {
    id: stateFile
    path: root.runtimeDir + "/tyler-juice/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var state = JSON.parse(text())
        if (state && (state.motion === "full" || state.motion === "reduced")) root.motion = state.motion
      } catch (e) {
        // Keep the last good value.
      }
    }
  }

  IpcHandler {
    target: "tyler.moments"

    function flash(kind: string): string {
      var k = String(kind || "")
      if (k === "theme") return root.playTheme(true)
      if (k === "screenshot") { root.playFlash(""); return "ok" }
      return "unknown kind: use screenshot or theme"
    }

    function screenshot(path: string, monitor: string): string {
      root.playFlash(monitor)
      if (root.validShotPath(path)) root.showShot(String(path), monitor)
      return "ok"
    }

    function status(): string {
      return JSON.stringify({
        motion: root.motion,
        sweeping: root.sweepActive,
        flashing: root.flashActive,
        thumbnail: root.shotVisible,
        result: root.shotResult
      })
    }

    function ping(): string { return "ok" }
  }

  // ---- surfaces -----------------------------------------------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData

      screen: modelData
      readonly property string screenName: String(modelData && modelData.name || "")
      readonly property bool flashHere: root.flashActive && root.flashScreen === win.screenName
      readonly property bool thumbHere: root.shotVisible && root.shotScreen === win.screenName

      visible: root.sweepActive || win.flashHere || win.thumbHere
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "tyler-moments"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Input only where the thumbnail is; the sweep and flash never take a
      // click from the desktop underneath.
      mask: Region { item: win.thumbHere ? thumbCard : null }

      // Theme sweep band. Its position is global, so it leaves one monitor's
      // right edge as it enters the next one's left edge.
      Item {
        id: sweepLayer
        anchors.fill: parent
        visible: root.sweepActive && !root.reduced

        readonly property real slant: 0.18
        readonly property real lean: slant * height
        readonly property real bandWidth: Math.max(Style.space(220), win.width * 0.22)
        readonly property real travelStart: root.desktopSpan.min - bandWidth - lean
        readonly property real travelEnd: root.desktopSpan.max + lean
        readonly property real globalX: travelStart + (travelEnd - travelStart) * root.sweepProgress

        Rectangle {
          id: band
          x: sweepLayer.globalX - (win.modelData ? win.modelData.x : 0)
          y: 0
          width: sweepLayer.bandWidth
          height: sweepLayer.height
          // Lean forward like "/", the same slant as Omarchy's wallpaper reveal.
          transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, -sweepLayer.slant, 0, sweepLayer.lean,
                                 0, 1, 0, 0,
                                 0, 0, 1, 0,
                                 0, 0, 0, 1)
          }
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0) }
            GradientStop { position: 0.38; color: Util.alpha(Color.accent, 0.10) }
            GradientStop { position: 0.5; color: Util.alpha(Color.accent, 0.20) }
            GradientStop { position: 0.62; color: Util.alpha(Color.accent, 0.10) }
            GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0) }
          }

          // Leading edge: a hairline of the new foreground gives the band a
          // readable front on light themes where a pale accent washes out.
          Rectangle {
            x: Math.round(parent.width * 0.62)
            width: Math.max(1, Style.space(2))
            height: parent.height
            color: Util.alpha(Color.foreground, 0.14)
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.sweepActive && root.reduced
        color: Util.alpha(Color.accent, 0.08)
        opacity: root.washOpacity
      }

      // Screenshot edge flash: a faint frame of foreground that fades inward.
      Item {
        id: flashLayer
        anchors.fill: parent
        visible: win.flashHere
        opacity: root.flashOpacity

        readonly property real depth: Math.max(12, Style.space(22))
        readonly property color edge: Util.alpha(Color.foreground, 0.22)
        readonly property color clear: Util.alpha(Color.foreground, 0)

        Rectangle {
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: flashLayer.depth
          gradient: Gradient {
            GradientStop { position: 0.0; color: flashLayer.edge }
            GradientStop { position: 1.0; color: flashLayer.clear }
          }
        }
        Rectangle {
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: flashLayer.depth
          gradient: Gradient {
            GradientStop { position: 0.0; color: flashLayer.clear }
            GradientStop { position: 1.0; color: flashLayer.edge }
          }
        }
        Rectangle {
          anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
          width: flashLayer.depth
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: flashLayer.edge }
            GradientStop { position: 1.0; color: flashLayer.clear }
          }
        }
        Rectangle {
          anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
          width: flashLayer.depth
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: flashLayer.clear }
            GradientStop { position: 1.0; color: flashLayer.edge }
          }
        }
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.width: Math.max(1, Style.space(2))
          border.color: Util.alpha(Color.foreground, 0.32)
        }
      }

      // Screenshot thumbnail. Rests in the bottom-right corner, then rises to
      // the notification chip (top right) and fades there.
      BorderSurface {
        id: thumbCard

        readonly property real margin: Style.space(24)
        readonly property real pad: Style.space(8)
        readonly property real imageWidth: Style.space(240)
        readonly property real imageHeight: shotImage.status === Image.Ready && shotImage.implicitWidth > 0
          ? Math.min(Style.space(180), Math.round(imageWidth * shotImage.implicitHeight / shotImage.implicitWidth))
          : Math.round(imageWidth * 9 / 16)
        readonly property real restX: win.width - margin - width
        readonly property real restY: win.height - margin - height
        // Top-right corner of the card ends near the notification chip.
        readonly property real chipRight: win.width - Style.space(28)
        readonly property real chipTop: Style.space(4)
        readonly property real travel: root.reduced ? 0 : root.shotLeave
        readonly property real enterOffset: root.reduced ? 0 : (1 - root.shotEnter) * Style.space(48)

        visible: win.thumbHere
        width: thumbCard.borderLeft + pad + imageWidth + pad + thumbCard.borderRight
        height: thumbCard.borderTop + pad + imageHeight + Style.space(6) + caption.implicitHeight + pad + thumbCard.borderBottom
        x: restX + enterOffset + (chipRight - (restX + width)) * travel
        y: restY + (chipTop - restY) * travel
        transformOrigin: Item.TopRight
        scale: 1 - 0.85 * travel
        opacity: root.shotEnter * (1 - root.shotLeave)

        color: Util.alpha(Color.background, 0.97)
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        Image {
          id: shotImage
          x: thumbCard.borderLeft + thumbCard.pad
          y: thumbCard.borderTop + thumbCard.pad
          width: thumbCard.imageWidth
          height: thumbCard.imageHeight
          source: win.thumbHere ? Util.fileUrl(root.shotPath) : ""
          sourceSize.width: Math.round(thumbCard.imageWidth * 2)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
        }

        Text {
          id: caption
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          y: shotImage.y + shotImage.height + Style.space(6)
          width: thumbCard.imageWidth
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          text: root.shotResult === "sending" ? "Sending to agent…"
            : root.shotResult === "sent" ? "Sent to agent"
            : root.shotResult === "failed" ? "No agent took it"
            : "Click to send to agent"
          color: root.shotResult === "sent" ? Color.accent
            : root.shotResult === "failed" ? Color.urgent
            : Color.popups.text
          opacity: root.shotResult !== "" || root.shotHovered ? 1 : 0.55
          Behavior on opacity { NumberAnimation { duration: Motion.duration(Motion.ack, root.motion) } }
        }

        // Accepted: the frame takes the accent for the rest of its short life.
        Rectangle {
          anchors.fill: parent
          radius: thumbCard.radius
          color: "transparent"
          border.width: Math.max(1, Style.space(2))
          border.color: root.shotResult === "failed" ? Color.urgent : Color.accent
          opacity: root.shotResult === "sent" || root.shotResult === "failed" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Motion.duration(Motion.ack, root.motion) } }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: root.shotHovered = containsMouse
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.leaveShot()
            else root.sendShot()
          }
        }
      }
    }
  }
}
