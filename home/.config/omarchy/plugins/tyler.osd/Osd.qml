import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "OsdModel.js" as OsdModel
import "../tyler.juice/Motion.js" as Motion

// Clone of omarchy.osd. Same IPC target ("osd"), same summon payloads, same
// timing; progress OSDs (volume, brightness, ...) draw as an instrument dial:
// a 270° track in muted foreground, the value arc in accent, the icon in the
// middle and the readout in the dial's open foot. Message-only OSDs (media,
// toggles) keep Omarchy's single-row card.

Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200

  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0
  // Muted is not live: the arc keeps its length but drops the accent.
  readonly property bool mutedState: iconKey.indexOf("mute") !== -1 || iconKey.indexOf("-off") !== -1

  // Reduced motion from the juice state bus: the arc jumps instead of sweeping.
  property string motion: "full"

  // The message card is built out of measured columns instead of fixed widths,
  // so it keeps exactly `pad` between border and content on every side
  // whatever glyph or message it carries. Messages grow with their text up to
  // `maxMessageWidth` and elide beyond it.
  readonly property int pad: Style.space(16)
  readonly property int gap: Style.space(16)
  // A glyph next to a message reads airier than it measures: the icon outline
  // and the letterforms both fall away from their ink extremes, so the space
  // between them opens up well past the nominal gap. Text takes two thirds of
  // it.
  readonly property int messageGap: Math.round(root.gap * 2 / 3)
  readonly property int maxMessageWidth: root.mediaOsd ? Style.space(325) : Style.space(190)

  // Dial geometry. Ticks sit on the outside of the arc; majors at 0, 50, 100.
  readonly property int dialSize: Style.space(112)
  readonly property int dialStroke: Math.max(Style.space(6), Style.spacing.sm)
  readonly property int tickWidth: Math.max(1, Style.space(2))
  readonly property int minorTick: Style.space(4)
  readonly property int majorTick: Style.space(7)
  readonly property int tickGap: Style.space(4)
  readonly property real dialRadius: root.dialSize / 2 - root.majorTick - root.tickGap - root.dialStroke / 2
  readonly property real fraction: root.hasProgress ? root.value / root.maxValue : 0

  // Nerd Font glyphs draw well outside their monospace cell, so the icon
  // column is measured by ink rather than by advance width.
  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int contentWidth: root.hasProgress
    ? root.dialSize
    : (root.message === "" ? root.iconInkWidth : root.iconInkWidth + root.messageGap + root.messageWidth)
  readonly property int contentHeight: root.hasProgress ? root.dialSize : Style.font.displayLarge

  // Displayed sweep of the value arc; animates only while the OSD stays open,
  // so a fresh OSD starts at its new value.
  property real shownFraction: root.fraction
  Behavior on shownFraction {
    enabled: root.opened && root.motion !== "reduced"
    NumberAnimation { duration: Motion.ack; easing.type: Easing.OutCubic }
  }

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    // Update before opening so a fresh OSD starts at its new value; only
    // subsequent updates while it remains open animate the dial.
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    opened = true
    tick(next)
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  // One tick per key step, played through the output it just set, so the
  // tick itself says how loud things now are.
  function tick(next) {
    if (!next.hasProgress) return
    var key = String(next.iconKey || "")
    var name = key.indexOf("volume") === 0 ? "volume-tick"
      : (key === "brightness" || key === "display") ? "brightness-tick" : ""
    if (name) Quickshell.execDetached([(Quickshell.env("HOME") || "") + "/.local/bin/juice-sound", name])
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    } catch (e) {}
  }

  function close() { opened = false }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
  }

  TextMetrics {
    id: iconMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    text: root.icon
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tyler-juice/state.json"
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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only surface: keep the layer-shell input region empty so the OSD
    // never blocks clicks to the desktop below it.
    mask: Region {}

    BorderSurface {
      id: card
      width: card.borderLeft + root.pad + root.contentWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + root.contentHeight + root.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0

      // Progress: the dial.
      Item {
        id: dial
        visible: root.hasProgress
        x: card.borderLeft + root.pad
        y: card.borderTop + root.pad
        width: root.dialSize
        height: root.dialSize

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          antialiasing: true

          // Track: 270° open at the bottom, like a gauge.
          ShapePath {
            fillColor: "transparent"
            strokeColor: Util.alpha(Color.popups.text, 0.2)
            strokeWidth: root.dialStroke
            capStyle: ShapePath.RoundCap
            PathAngleArc {
              centerX: dial.width / 2
              centerY: dial.height / 2
              radiusX: root.dialRadius
              radiusY: root.dialRadius
              startAngle: 135
              sweepAngle: 270
            }
          }

          // Value arc. A zero-length round-capped arc would still draw a dot,
          // so it goes transparent at zero.
          ShapePath {
            fillColor: "transparent"
            strokeColor: root.shownFraction <= 0.001 ? "transparent"
              : (root.mutedState ? Util.alpha(Color.popups.text, 0.5) : Color.accent)
            strokeWidth: root.dialStroke
            capStyle: ShapePath.RoundCap
            PathAngleArc {
              centerX: dial.width / 2
              centerY: dial.height / 2
              radiusX: root.dialRadius
              radiusY: root.dialRadius
              startAngle: 135
              sweepAngle: 270 * Math.max(0, Math.min(1, root.shownFraction))
            }
          }
        }

        // Scale ticks every 10%, rotated about the dial's centre. Ticks the
        // value has passed take the arc's colour at reduced strength.
        Repeater {
          model: 11
          Item {
            id: tick
            required property int index
            readonly property bool major: tick.index % 5 === 0
            readonly property bool passed: !root.mutedState && root.shownFraction > 0.001
              && tick.index / 10 <= root.shownFraction + 0.0001
            width: dial.width
            height: dial.height
            rotation: -135 + tick.index * 27
            Rectangle {
              x: Math.round((tick.width - width) / 2)
              y: 0
              width: root.tickWidth
              height: tick.major ? root.majorTick : root.minorTick
              radius: width / 2
              color: tick.passed ? Util.alpha(Color.accent, 0.75) : Util.alpha(Color.popups.text, 0.3)
            }
          }
        }

        OpticalGlyph {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -Style.space(4)
          width: parent.width
          height: Style.font.display
          text: root.icon
          fontSize: Style.font.display
          color: Color.popups.text
        }

        // Readout in the dial's open foot.
        Text {
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          text: root.message
          font: messageMetrics.font
          color: Color.popups.text
          maximumLineCount: 1
        }
      }

      // Message: Omarchy's single row, unchanged.
      Row {
        visible: !root.hasProgress
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.messageGap
        Item {
          width: root.iconInkWidth
          height: parent.height
          Text {
            textFormat: Text.PlainText
            // Sit the glyph's ink flush in the column.
            x: Math.round(-iconMetrics.tightBoundingRect.x)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font: iconMetrics.font
            color: Color.popups.text
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: root.message !== ""
          width: root.messageWidth
          horizontalAlignment: Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font: messageMetrics.font
          color: Color.popups.text
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }
}
