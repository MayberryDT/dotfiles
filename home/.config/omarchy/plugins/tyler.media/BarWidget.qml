import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "MediaModel.js" as MediaModel
import "ServiceBridge.js" as ServiceBridge
import "../tyler.juice/Motion.js" as Motion

// Now playing from cliamp. At rest: a state mark (or cliamp's ten bands while
// music plays), a static shortened title and an accent progress line. Hover
// widens it to previous / play-pause / next and the volume. Click opens the
// panel; middle-click plays or pauses; right-click skips ahead; scroll sets
// the volume.
BarWidget {
  id: root
  moduleName: "tyler.media"

  property var service: null
  function resolveService() {
    var next = ServiceBridge.current()
    if (next !== service) service = next
  }

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  readonly property string status: service ? service.status : "absent"
  readonly property bool reduced: service ? service.reducedMotion : false
  readonly property bool connected: service ? service.connected : false
  readonly property string heading: service ? service.targetState : "stopped"
  function dur(ms) { return Motion.duration(ms, reduced ? "reduced" : "full") }

  readonly property int maxTitleWidth: Math.max(60, Number(setting("maxTitleWidth", 180)) || 180)
  readonly property bool visualizerEnabled: setting("visualizer", true) !== false
  readonly property bool showWhenAbsent: setting("showWhenAbsent", true) !== false

  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var glyphs: ({
    play: String.fromCodePoint(0xF040A),
    pause: String.fromCodePoint(0xF03E4),
    stop: String.fromCodePoint(0xF04DB),
    next: String.fromCodePoint(0xF04AD),
    previous: String.fromCodePoint(0xF04AE),
    music: String.fromCodePoint(0xF075A),
    loading: String.fromCodePoint(0xF0772),
    alert: String.fromCodePoint(0xF05D6)
  })

  readonly property bool bandsHaveSignal: {
    var b = service ? service.bands : []
    for (var i = 0; i < b.length; i++) if (b[i] > 0.02) return true
    return false
  }
  readonly property bool showBars: visualizerEnabled && !vertical && !reduced && bandsHaveSignal
    && (status === "playing" || status === "paused")

  readonly property string markGlyph: {
    switch (status) {
    case "error": return glyphs.alert
    case "absent": return glyphs.music
    case "starting": return glyphs.music
    case "buffering": return glyphs.loading
    case "working": return heading === "playing" ? glyphs.play : glyphs.pause
    case "playing": return glyphs.play
    case "paused": return glyphs.pause
    default: return glyphs.stop
    }
  }
  readonly property color markColor: {
    if (status === "error") return urgentColor
    if (status === "playing") return Color.accent
    if (status === "absent") return Util.alpha(fg, 0.42)
    if (status === "paused" || status === "stopped") return Util.alpha(fg, 0.6)
    return fg
  }
  readonly property bool breathing: status === "working" || status === "buffering" || status === "starting"

  // A scroll shows the volume in place of the title for a moment.
  property bool volumeFlash: false
  readonly property string volumeText: service ? MediaModel.formatDb(service.volume) : ""
  readonly property string titleText: {
    if (volumeFlash) return volumeText
    if (status === "error") return service.errorText
    if (status === "absent") return ""
    if (status === "starting") return "Starting cliamp"
    return service ? service.title : ""
  }
  readonly property color titleColor: status === "error" ? urgentColor
    : (status === "paused" || status === "stopped" || status === "starting") ? Util.alpha(fg, 0.65) : fg

  readonly property bool expanded: hover.hovered && !vertical && connected && !popupOpen

  readonly property string tooltipText: {
    if (!service || status === "absent")
      return "cliamp isn't running\nClick for stations \u00b7 middle-click starts the focus station"
    if (status === "starting") return "Starting cliamp\u2026"
    var lines = []
    if (status === "error") lines.push(service.errorText)
    if (service.title) lines.push(service.title)
    if (service.subtitle) lines.push(service.subtitle)
    if (service.chapter)
      lines.push("Chapter " + (service.chapterIndex + 1) + " of " + service.chapters.length)
    if (service.hasProgress)
      lines.push(MediaModel.formatTime(service.position) + " / " + MediaModel.formatTime(service.snap.duration))
    if (status === "buffering") lines.push("Buffering\u2026")
    lines.push("Click: panel \u00b7 Middle: play/pause \u00b7 Right: next \u00b7 Scroll: volume")
    return lines.join("\n")
  }

  readonly property string demandKey: "tyler.media:" + String(root)
  readonly property bool wantsBands: visible && visualizerEnabled && !vertical
  function syncDemand() {
    if (service) service.setVisualizerDemand(demandKey, wantsBands)
  }
  onWantsBandsChanged: syncDemand()
  onServiceChanged: syncDemand()

  onPopupOpenChanged: {
    if (!service) return
    if (popupOpen) {
      service.panelOpened()
      if (bar) bar.hideTooltip(root)
    } else {
      service.panelClosed()
    }
  }

  onTooltipTextChanged: if (hover.hovered && bar && !popupOpen) bar.showTooltip(root, tooltipText)

  function isOnFocusedScreen() {
    var w = root.QsWindow.window
    var mine = w && w.screen ? String(w.screen.name || "") : ""
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    return !mine || !focused || mine === focused
  }

  Connections {
    target: root.service
    function onPanelRequest(mode) {
      if (!root.isOnFocusedScreen()) return
      if (mode === "open") root.open()
      else if (mode === "close") root.close()
      else root.toggle()
    }
  }

  Component.onCompleted: resolveService()
  Component.onDestruction: {
    if (service) {
      service.setVisualizerDemand(demandKey, false)
      if (popupOpen) service.panelClosed()
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: !root.service
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  Timer {
    id: volumeFlashTimer
    interval: 1200
    onTriggered: root.volumeFlash = false
  }

  function acknowledge() {
    ackAnimation.restart()
  }

  property real wheelRemainder: 0
  function wheel(delta) {
    if (!service || !connected) return
    wheelRemainder += delta
    var steps = Math.trunc(wheelRemainder / 120)
    if (steps === 0) return
    wheelRemainder -= steps * 120
    service.adjustVolume(steps)
    volumeFlash = true
    volumeFlashTimer.restart()
  }

  visible: !!service && (status !== "absent" || showWhenAbsent)
  implicitWidth: vertical ? barSize : content.implicitWidth + Style.space(14)
  implicitHeight: vertical ? verticalContent.implicitHeight + Style.space(10) : barSize

  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered && !root.popupOpen) root.bar.showTooltip(root, root.tooltipText)
      else root.bar.hideTooltip(root)
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (!root.service) return
      if (mouse.button === Qt.LeftButton) {
        root.toggle()
      } else if (mouse.button === Qt.MiddleButton) {
        root.acknowledge()
        root.service.togglePlay(false)
      } else if (root.connected) {
        root.acknowledge()
        root.service.next(false)
      }
    }
    onWheel: function(event) { root.wheel(event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x) }
  }

  // ------------------------------------------------------------ mark

  component Mark: Item {
    id: mark
    implicitWidth: root.showBars ? bars.implicitWidth : glyph.implicitWidth
    implicitHeight: glyph.implicitHeight

    Text {
      id: glyph
      anchors.centerIn: parent
      visible: !root.showBars
      textFormat: Text.PlainText
      text: root.markGlyph
      color: root.markColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: root.dur(Motion.ack) }
      }
    }

    Item {
      id: bars
      visible: root.showBars
      anchors.centerIn: parent
      readonly property real barWidth: Math.max(2, Style.space(2))
      readonly property real gap: Math.max(1, Style.space(1))
      implicitWidth: barWidth * 10 + gap * 9
      implicitHeight: Style.space(12)
      width: implicitWidth
      height: implicitHeight

      Repeater {
        model: 10
        Rectangle {
          required property int index
          readonly property real level: root.service && root.service.bands.length > index ? root.service.bands[index] : 0
          x: index * (bars.barWidth + bars.gap)
          width: bars.barWidth
          height: Math.max(1, Math.round(bars.height * Math.min(1, level)))
          y: bars.height - height
          radius: width / 2
          color: root.status === "playing" ? Color.accent : Util.alpha(root.fg, 0.45)
          Behavior on height {
            enabled: root.status === "playing"
            NumberAnimation { duration: 66 }
          }
        }
      }
    }
  }

  // A press is acknowledged at once: a small squeeze of the mark, or with
  // reduced motion a brief dip in its opacity.
  property real ackScale: 1
  property real ackOpacity: 1
  property real breath: 1
  readonly property real markOpacity: (breathing ? (reduced ? 0.6 : breath) : 1) * ackOpacity

  SequentialAnimation {
    id: ackAnimation
    NumberAnimation {
      target: root
      property: root.reduced ? "ackOpacity" : "ackScale"
      to: root.reduced ? 0.55 : 0.8
      duration: Motion.ack / 2
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: root.reduced ? "ackOpacity" : "ackScale"
      to: 1
      duration: Motion.ack
      easing.type: Easing.OutCubic
    }
  }

  // Slow breath while cliamp is working on a press or buffering.
  SequentialAnimation {
    running: root.breathing && !root.reduced
    loops: Animation.Infinite
    onRunningChanged: if (!running) root.breath = 1
    NumberAnimation { target: root; property: "breath"; to: 0.4; duration: Motion.breathe; easing.type: Easing.InOutCubic }
    NumberAnimation { target: root; property: "breath"; to: 1; duration: Motion.breathe; easing.type: Easing.InOutCubic }
  }

  // ------------------------------------------------------------ horizontal

  Row {
    id: content
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(6)

    Mark {
      id: markH
      anchors.verticalCenter: parent.verticalCenter
      opacity: root.markOpacity
      scale: root.ackScale
    }

    Text {
      id: titleLabel
      anchors.verticalCenter: parent.verticalCenter
      visible: text !== ""
      textFormat: Text.PlainText
      text: root.titleText
      color: root.titleColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      maximumLineCount: 1
      width: Math.min(root.maxTitleWidth, implicitWidth)
    }

    Item {
      id: controlsClip
      anchors.verticalCenter: parent.verticalCenter
      height: controls.implicitHeight
      width: root.expanded ? controls.implicitWidth : 0
      clip: true
      visible: width > 0
      opacity: root.expanded ? 1 : 0
      Behavior on width { NumberAnimation { duration: root.dur(Motion.drawer); easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: root.dur(Motion.drawer); easing.type: Easing.OutCubic } }

      Row {
        id: controls
        spacing: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter

        Item { width: Style.space(4); height: 1 }

        HoverControl {
          glyph: root.glyphs.previous
          onActivated: root.service.previous(false)
        }
        HoverControl {
          glyph: root.heading === "playing" ? root.glyphs.pause : root.glyphs.play
          onActivated: root.service.togglePlay(false)
        }
        HoverControl {
          glyph: root.glyphs.next
          onActivated: root.service.next(false)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          leftPadding: Style.space(4)
          textFormat: Text.PlainText
          text: root.volumeText
          color: Util.alpha(root.fg, 0.75)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  component HoverControl: Text {
    id: control
    property string glyph: ""
    signal activated()
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    textFormat: Text.PlainText
    text: glyph
    leftPadding: Style.space(3)
    rightPadding: Style.space(3)
    color: controlArea.containsMouse ? root.fg : Util.alpha(root.fg, 0.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    MouseArea {
      id: controlArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.acknowledge()
        control.activated()
      }
    }
  }

  // Thin accent progress line: the current chapter in a mix, otherwise the track.
  Rectangle {
    id: progressTrack
    visible: !root.vertical && root.service && root.service.hasProgress
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(2)
    x: content.x
    width: markH.width + (titleLabel.visible ? titleLabel.width + content.spacing : 0)
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: Util.alpha(root.fg, 0.12)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      radius: parent.radius
      width: parent.width * (root.service ? root.service.progress : 0)
      color: Color.accent
      opacity: root.status === "playing" || root.status === "buffering" ? 1 : 0.5
    }
  }

  // ------------------------------------------------------------ vertical

  Column {
    id: verticalContent
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(3)

    Mark {
      id: markV
      anchors.horizontalCenter: parent.horizontalCenter
      opacity: root.markOpacity
      scale: root.ackScale
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.service && root.service.hasProgress
      width: Math.round(root.barSize * 0.5)
      height: Math.max(1, Style.space(2))
      radius: height / 2
      color: Util.alpha(root.fg, 0.12)
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: parent.radius
        width: parent.width * (root.service ? root.service.progress : 0)
        color: Color.accent
      }
    }
  }

  // ------------------------------------------------------------ panel

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(panel.implicitHeight)

    MediaPanel {
      id: panel
      anchors.fill: parent
      service: root.service
      bar: root.bar
      active: root.popupOpen
      tintArt: root.setting("tintArt", false) === true
      onRequestClose: root.close()
    }
  }
}
