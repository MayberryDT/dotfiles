import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "WorkspaceNames.js" as Names
import "HubBridge.js" as HubBridge
import "../tyler.juice/Motion.js" as Motion

// Workspace indicator, cloned from omarchy.workspaces.
//
// Each workspace shows the icon of its most recently focused window at number
// width; an empty one shows its number. Brightness carries the state:
//   empty      Color.muted number
//   occupied   bar foreground, a little dimmed
//   current    full bar foreground and a thin Color.accent underline
//   attention  Color.urgent (a window asked for attention, or the workspace
//              holds the Herdr window while an agent is blocked), one pulse
// The derived name is in the tooltip and, while Super is held, in a small
// label strip (the "peek") beside the row. Names never sit on the bar.
BarWidget {
  id: root
  moduleName: "tyler.workspaces"

  readonly property int alwaysShown: Math.max(1, Math.min(10, Number(setting("alwaysShown", 5)) || 5))

  // ---------------------------------------------------------------- hub

  property var hub: null
  function resolveHub() {
    var next = HubBridge.current()
    if (next !== root.hub) root.hub = next
  }
  Component.onCompleted: resolveHub()

  Timer {
    interval: 250
    repeat: true
    running: !root.hub
    triggeredOnStart: true
    onTriggered: root.resolveHub()
  }

  readonly property var model: root.hub ? root.hub.workspaces : ({})
  readonly property bool reducedMotion: root.hub ? root.hub.reducedMotion === true : false
  readonly property bool peeking: root.hub ? root.hub.peeking === true : false

  // ---------------------------------------------------------------- monitor

  // One row per monitor. A workspace number spans both monitors (see
  // Names.pairFor), so "current" is the number this bar's monitor shows.
  readonly property var barWindow: root.QsWindow.window
  readonly property var barScreen: barWindow ? barWindow.screen : null
  readonly property var barMonitor: barScreen ? Hyprland.monitorFor(barScreen) : null
  readonly property int currentId: {
    var monitor = root.barMonitor
    if (monitor && monitor.activeWorkspace) return Names.numberOf(monitor.activeWorkspace.id)
    return Hyprland.focusedWorkspace ? Names.numberOf(Hyprland.focusedWorkspace.id) : 0
  }
  readonly property bool monitorFocused: root.barMonitor === null || Hyprland.focusedMonitor === root.barMonitor

  readonly property color barFg: root.bar ? root.bar.barForeground : Color.foreground
  readonly property string position: root.bar && root.bar.position ? String(root.bar.position) : "top"

  // The Hyprland workspaces (one per monitor) that make up workspace number n.
  function halves(n) {
    var out = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (Names.numberOf(values[i].id) === n) out.push(values[i])
    return out
  }

  function workspaceIds() {
    var ids = []
    for (var n = 1; n <= root.alwaysShown; n++) ids.push(n)
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = Names.numberOf(values[i].id)
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  readonly property var ids: workspaceIds()

  // Through the flow script, so both monitors switch together.
  function focusWorkspace(id) {
    var n = Math.trunc(Number(id))
    if (!(n > 0)) return
    Util.execArgv([Quickshell.env("HOME") + "/.local/bin/zet-workspace-flow", "goto", String(n)])
  }

  // A themed symbolic icon recolours cleanly, so it wins over the full-colour
  // one when the theme has it. A full-colour icon is shown desaturated instead:
  // recoloured to one colour it collapses into a featureless disc.
  function iconSource(icon) {
    var value = String(icon || "")
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var symbolic = Quickshell.iconPath(value + "-symbolic", true)
    return symbolic !== "" ? symbolic : Quickshell.iconPath(value, true)
  }

  function iconIsSymbolic(icon) {
    var value = String(icon || "")
    if (!value || value.charAt(0) === "/" || value.indexOf("://") !== -1) return /-symbolic(\.[a-z]+)?$/.test(value)
    return /-symbolic$/.test(value) || Quickshell.iconPath(value + "-symbolic", true) !== ""
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.ids.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: slots
      model: root.ids

      Item {
        id: slot
        required property int modelData

        readonly property var info: Names.pairFor(root.model, modelData)
        readonly property var halves: root.halves(modelData)
        readonly property bool occupied: info.occupied
          || halves.some(function(w) { return w.toplevels.values.length > 0 })
        readonly property bool current: root.currentId === modelData
        readonly property bool attention: info.attention || halves.some(function(w) { return w.urgent === true })
        readonly property color tone: attention ? Color.urgent : (occupied || current ? root.barFg : Color.muted)
        readonly property real baseOpacity: attention || current || !occupied ? 1 : 0.72
        readonly property string source: occupied ? root.iconSource(info.icon) : ""
        readonly property bool iconShown: source !== "" && iconImage.status === Image.Ready
        // Symbolic icons and the urgent state take the state colour; a
        // full-colour icon stays greyscale and lets opacity carry the state.
        readonly property bool colourise: attention || (occupied && root.iconIsSymbolic(info.icon))
        readonly property string label: occupied && info.glyph ? info.glyph : info.number

        property real pulse: 1
        opacity: pulse

        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        // One slow dip when something starts needing Tyler; never a loop.
        onAttentionChanged: {
          if (attention && !root.reducedMotion) pulseAnimation.restart()
          else { pulseAnimation.stop(); slot.pulse = 1 }
        }

        SequentialAnimation {
          id: pulseAnimation
          NumberAnimation { target: slot; property: "pulse"; to: 0.35; duration: Motion.pulse * 0.4; easing.type: Easing.InOutCubic }
          NumberAnimation { target: slot; property: "pulse"; to: 1; duration: Motion.pulse * 0.6; easing.type: Easing.InOutCubic }
        }

        WidgetButton {
          id: button
          anchors.fill: parent
          bar: root.bar
          text: slot.label
          hasVisualContent: true
          labelVisible: !slot.iconShown
          foreground: slot.tone
          opacity: slot.baseOpacity
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          tooltipText: Names.tooltipFor(slot.info)
          onPressed: function() { root.focusWorkspace(slot.modelData) }

          // Kept as a hidden layer so the effect can sample it; the effect
          // recolours it to the state's theme role, as the stock tray does.
          // The layer stays on: enabling it only once the slot had an icon
          // left the effect drawing nothing after the workspace had been
          // empty. Synchronous loading keeps an icon change from showing a
          // blank frame.
          Image {
            id: iconImage
            anchors.centerIn: parent
            width: Math.round(button.fontSize * 1.25)
            height: width
            source: slot.source
            fillMode: Image.PreserveAspectFit
            sourceSize.width: Math.round(width * Screen.devicePixelRatio)
            sourceSize.height: Math.round(height * Screen.devicePixelRatio)
            asynchronous: false
            smooth: true
            visible: false
            layer.enabled: true
          }

          MultiEffect {
            anchors.fill: iconImage
            source: iconImage
            visible: slot.iconShown
            colorization: slot.colourise ? 1.0 : 0.0
            colorizationColor: slot.tone
            saturation: slot.colourise ? 0.0 : -1.0

            Behavior on colorizationColor {
              ColorAnimation { duration: Motion.duration(Motion.ack, root.reducedMotion ? "reduced" : "full") }
            }
          }
        }

        // Current-workspace mark on the edge facing the desktop. Dimmer when
        // the keyboard is on another monitor.
        Rectangle {
          readonly property int thickness: Math.max(1, Style.space(2))
          readonly property int extent: Math.round(root.barSize * 0.36)

          color: slot.attention ? Color.urgent : Color.accent
          radius: thickness / 2
          opacity: slot.current ? (root.monitorFocused ? 0.95 : 0.45) : 0
          visible: opacity > 0
          width: root.vertical ? thickness : extent
          height: root.vertical ? extent : thickness
          x: root.vertical
            ? (root.position === "right" ? Style.space(2) : slot.width - thickness - Style.space(2))
            : (slot.width - width) / 2
          y: root.vertical
            ? (slot.height - height) / 2
            : (root.position === "bottom" ? Style.space(3) : slot.height - thickness - Style.space(3))

          Behavior on opacity {
            NumberAnimation { duration: Motion.duration(Motion.ack, root.reducedMotion ? "reduced" : "full"); easing.type: Easing.OutCubic }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- peek

  // Horizontal bar: one compact strip beside the bar, starting under the row,
  // listing the occupied (and current) workspaces as icon · number · name.
  // Vertical bar: one label beside each indicator, lined up with it.
  readonly property var peekIds: {
    var out = []
    for (var i = 0; i < root.ids.length; i++) {
      var id = root.ids[i]
      if (Names.pairFor(root.model, id).occupied || id === root.currentId) out.push(id)
    }
    return out
  }

  PopupWindow {
    id: peekWindow

    readonly property int margin: Style.gapsOut
    readonly property int slide: root.reducedMotion ? 0 : Style.space(4)

    visible: root.peeking || peekContent.opacity > 0
    color: "transparent"
    implicitWidth: Math.max(1, peekContent.implicitWidth)
    implicitHeight: Math.max(1, peekContent.implicitHeight)
    // Click-through: the labels are for reading only.
    mask: Region {}

    anchor {
      window: root.barWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var window = root.barWindow
        if (!window) return
        var localX = 0
        var localY = root.height + peekWindow.margin
        if (root.position === "bottom") {
          localY = -peekWindow.implicitHeight - peekWindow.margin
        } else if (root.position === "left") {
          localX = root.width + peekWindow.margin
          localY = 0
        } else if (root.position === "right") {
          localX = -peekWindow.implicitWidth - peekWindow.margin
          localY = 0
        }
        var point = window.contentItem.mapFromItem(root, localX, localY)
        peekWindow.anchor.rect.x = Math.round(point.x)
        peekWindow.anchor.rect.y = Math.round(point.y)
      }
    }

    onVisibleChanged: if (visible) peekWindow.anchor.updateAnchor()

    Item {
      id: peekContent
      anchors.fill: parent
      implicitWidth: root.vertical ? column.implicitWidth : strip.implicitWidth
      implicitHeight: root.vertical ? column.implicitHeight : strip.implicitHeight
      opacity: root.peeking ? 1 : 0

      Behavior on opacity {
        NumberAnimation {
          duration: root.peeking ? Motion.ack : Motion.drawer
          easing.type: root.peeking ? Easing.OutCubic : Easing.InOutCubic
        }
      }

      transform: Translate {
        x: root.vertical && !root.peeking ? (root.position === "right" ? peekWindow.slide : -peekWindow.slide) : 0
        y: !root.vertical && !root.peeking ? (root.position === "bottom" ? peekWindow.slide : -peekWindow.slide) : 0
        Behavior on x { NumberAnimation { duration: Motion.duration(Motion.drawer, root.reducedMotion ? "reduced" : "full"); easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Motion.duration(Motion.drawer, root.reducedMotion ? "reduced" : "full"); easing.type: Easing.OutCubic } }
      }

      // Horizontal: one card.
      BorderSurface {
        id: strip
        visible: !root.vertical && root.peekIds.length > 0
        implicitWidth: stripRow.implicitWidth + Style.spacing.md * 2
        implicitHeight: stripRow.implicitHeight + Style.spacing.sm * 2
        width: implicitWidth
        height: implicitHeight
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.flat(Util.alpha(Color.popups.text, 0.16), Math.max(1, Style.normalBorderWidth))

        Row {
          id: stripRow
          x: Style.spacing.md
          y: Style.spacing.sm
          spacing: Style.spacing.lg

          Repeater {
            model: root.peekIds

            PeekChip {
              required property int modelData
              required property int index
              workspaceId: modelData
              order: index
            }
          }
        }
      }

      // Vertical: one pill per indicator, at the indicator's height.
      Item {
        id: column
        visible: root.vertical
        property real widest: 1
        function measure() {
          var widest = 0
          for (var i = 0; i < pills.count; i++) {
            var pill = pills.itemAt(i)
            if (pill && pill.shown) widest = Math.max(widest, pill.implicitWidth)
          }
          column.widest = Math.max(1, widest)
        }
        implicitWidth: widest
        implicitHeight: Math.max(1, root.height)

        Repeater {
          id: pills
          model: root.vertical ? root.ids : []

          BorderSurface {
            id: pill
            required property int modelData
            required property int index

            readonly property bool shown: root.peekIds.indexOf(modelData) !== -1

            onShownChanged: column.measure()
            onImplicitWidthChanged: column.measure()
            Component.onCompleted: column.measure()

            visible: shown
            implicitWidth: pillChip.implicitWidth + Style.spacing.md * 2
            implicitHeight: pillChip.implicitHeight + Style.spacing.xs * 2
            width: implicitWidth
            height: implicitHeight
            x: root.position === "right" ? column.width - width : 0
            // Vertical slots are barSize tall, Style.space(2) apart (see grid).
            y: index * (root.barSize + Style.space(2)) + (root.barSize - height) / 2
            radius: Style.cornerRadius
            color: Color.popups.background
            borderSpec: Border.flat(Util.alpha(Color.popups.text, 0.16), Math.max(1, Style.normalBorderWidth))

            PeekChip {
              id: pillChip
              x: Style.spacing.md
              y: Style.spacing.xs
              workspaceId: pill.modelData
              order: root.peekIds.indexOf(pill.modelData)
            }
          }
        }
      }
    }
  }

  // icon · number · name, in the popup's text colour; state as on the bar.
  component PeekChip: Item {
    id: chip

    property int workspaceId: 0
    property int order: 0

    readonly property var info: Names.pairFor(root.model, workspaceId)
    readonly property bool current: workspaceId === root.currentId
    readonly property color tone: info.attention ? Color.urgent : Color.popups.text
    readonly property string source: info.occupied ? root.iconSource(info.icon) : ""
    readonly property bool iconShown: source !== "" && chipIcon.status === Image.Ready
    readonly property bool colourise: info.attention || (info.occupied && root.iconIsSymbolic(info.icon))

    implicitWidth: chipRow.implicitWidth
    implicitHeight: chipRow.implicitHeight + underline.height + Style.space(2)

    // Chips arrive one after another (Motion.stagger apart) and leave together.
    property bool revealed: false
    opacity: revealed && root.peeking ? 1 : 0
    Behavior on opacity {
      NumberAnimation { duration: Motion.ack; easing.type: Easing.OutCubic }
    }

    Timer {
      id: revealTimer
      interval: Math.max(1, chip.order * Motion.stagger)
      onTriggered: chip.revealed = true
    }

    function syncReveal() {
      if (!root.peeking) { revealTimer.stop(); chip.revealed = false }
      else if (root.reducedMotion || chip.order <= 0) chip.revealed = true
      else if (!chip.revealed) revealTimer.restart()
    }

    Connections {
      target: root
      function onPeekingChanged() { chip.syncReveal() }
    }
    Component.onCompleted: syncReveal()

    Row {
      id: chipRow
      spacing: Style.spacing.sm

      Item {
        width: Math.round(Style.font.body * 1.2)
        height: width
        anchors.verticalCenter: parent.verticalCenter

        Image {
          id: chipIcon
          anchors.fill: parent
          source: chip.source
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          asynchronous: false
          visible: false
          layer.enabled: true  // always on; see the bar slot icon
        }

        MultiEffect {
          anchors.fill: chipIcon
          source: chipIcon
          visible: chip.iconShown
          colorization: chip.colourise ? 1.0 : 0.0
          colorizationColor: chip.tone
          saturation: chip.colourise ? 0.0 : -1.0
        }

        Text {
          anchors.centerIn: parent
          visible: !chip.iconShown
          text: chip.info.occupied ? chip.info.glyph : ""
          textFormat: Text.PlainText
          color: chip.tone
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.info.number
        textFormat: Text.PlainText
        color: chip.info.attention ? Color.urgent : Color.popups.text
        opacity: 0.55
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.info.occupied ? chip.info.name : "empty"
        textFormat: Text.PlainText
        color: chip.tone
        opacity: chip.info.occupied ? (chip.current || chip.info.attention ? 1 : 0.8) : 0.5
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: chip.current
      }
    }

    Rectangle {
      id: underline
      anchors.left: chipRow.left
      anchors.right: chipRow.right
      anchors.top: chipRow.bottom
      anchors.topMargin: Style.space(2)
      height: Math.max(1, Style.space(2))
      radius: height / 2
      color: chip.info.attention ? Color.urgent : Color.accent
      opacity: chip.current ? 0.95 : 0
    }
  }
}
