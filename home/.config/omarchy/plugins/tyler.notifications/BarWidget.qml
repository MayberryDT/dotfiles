// Bar inbox for tyler.notifications. The cloned bar is service-less, so the
// daemon is reached through ServiceBridge rather than firstPartyServiceFor.
// The chip lights (accent; urgent for critical) while something is unseen,
// sleeps during automatic DND, and shows the held count once when it ends.
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui
import "NotificationLogic.js" as NotificationLogic
import "ServiceBridge.js" as ServiceBridge
import "components"
import "../tyler.juice/Motion.js" as Motion

BarWidget {
  id: root
  moduleName: "tyler.notifications"

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  property string query: ""
  property var filteredRows: []
  property var historyRows: []

  // Dismissed history entries, hidden until the next read no longer finds
  // their files (see dismiss()).
  property var hiddenHistoryKeys: ({})
  function historyKey(row) {
    if (row.id !== undefined && row.id !== null && row.id !== 0) return "id:" + row.id
    return "k:" + row.app + "|" + row.summary + "|" + row.timestamp
  }

  property var notificationService: null
  function resolveService() {
    var next = ServiceBridge.current()
    if (next !== notificationService) notificationService = next
  }

  // The service owns the tyler.notifications IPC target and routes
  // open/close/toggle to the chip on the focused monitor.
  Component.onCompleted: {
    resolveService()
    ServiceBridge.registerWidget(root)
  }
  Component.onDestruction: ServiceBridge.unregisterWidget(root)
  onNotificationServiceChanged: rebuildRows()

  function screenName() {
    var window = root.QsWindow.window
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  Timer {
    interval: 250
    repeat: true
    running: !root.notificationService
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  readonly property int liveCount: {
    var service = notificationService
    if (!service) return 0
    if (typeof service.unreadCount === "number") return service.unreadCount
    return service.popupModel ? service.popupModel.count : 0
  }
  readonly property string historyDir: notificationService && notificationService.historyDir
    ? String(notificationService.historyDir) : ""

  // ---- DND (guarded: lives on Omarchy's first-party service, not here).
  readonly property bool dndSupported: !!notificationService
    && typeof notificationService.doNotDisturb === "boolean"
    && typeof notificationService.setDoNotDisturb === "function"
  readonly property bool dndOn: dndSupported && notificationService.doNotDisturb
  function toggleDnd() {
    if (dndSupported) notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
  }

  // ---- arrival, automatic DND and digest (state lives on the service)
  readonly property bool autoDnd: !!notificationService && notificationService.autoDnd === true
  readonly property int unseenCount: notificationService ? Number(notificationService.unseenCount || 0) : 0
  readonly property int unseenCritical: notificationService ? Number(notificationService.unseenCritical || 0) : 0
  readonly property bool reducedMotion: !!notificationService && notificationService.reducedMotion === true
  // Automatic DND keeps the chip asleep unless a critical broke through.
  readonly property bool holdingQuiet: autoDnd && unseenCritical === 0
  readonly property bool lit: !dndOn && !holdingQuiet && unseenCount > 0
  property bool digestVisible: false
  property int digestShown: 0

  function showDigest() {
    var service = root.notificationService
    if (!service || root.dndOn) return
    var count = Number(service.digestCount || 0)
    if (count <= 0) return
    root.digestShown = count
    root.digestVisible = true
    digestTimer.restart()
  }

  Timer {
    id: digestTimer
    interval: Math.max(2400, Motion.longFade * 3)
    repeat: false
    onTriggered: root.digestVisible = false
  }

  Connections {
    target: root.notificationService
    ignoreUnknownSignals: true
    function onArrived(critical) {
      // Colour carries every arrival (see chipLabel). A critical one also
      // gets a single slow pulse, unless motion is reduced.
      if (root.dndOn || !critical || root.reducedMotion) return
      criticalPulse.stop()
      chipLabel.scale = 1
      criticalPulse.start()
    }
    function onDigestSerialChanged() { root.showDigest() }
  }

  // Shape carries the state as well as colour, so it reads on light themes
  // and over a transparent bar: bell-off (manual DND), bell-sleep (holding),
  // bell-ring (something unseen), bell-badge (live, all seen), bell (empty).
  readonly property string icon: {
    if (root.dndOn) return "󰂛"
    if (root.digestVisible) return "󰂞+" + (root.digestShown > 99 ? "99" : String(root.digestShown))
    if (root.holdingQuiet) return "󰂠"
    if (root.liveCount <= 0) return "󰂚"
    return (root.lit ? "󰂞" : "󱅫") + (root.liveCount > 9 ? "9+" : String(root.liveCount))
  }

  readonly property color restColor: {
    var fromBar = root.bar ? root.bar.barForeground : undefined
    if (fromBar !== undefined && fromBar !== null) return fromBar
    var bar = Commons.Color.bar
    var fallback = (bar && bar.text !== undefined && bar.text !== null) ? bar.text : Commons.Color.foreground
    return (fallback !== undefined && fallback !== null) ? fallback : "#a9b1d6"
  }
  readonly property color litColor: root.unseenCritical > 0
    ? ((Commons.Color.urgent !== undefined && Commons.Color.urgent !== null) ? Commons.Color.urgent : "#a55555")
    : root.colAccent
  readonly property color chipColor: root.lit || root.digestVisible ? root.litColor : root.restColor

  readonly property string autoDndText: {
    var reasons = root.notificationService && root.notificationService.autoDndReasons
      ? root.notificationService.autoDndReasons : []
    return reasons.length > 0 ? reasons.join(", ") : "auto"
  }
  readonly property int heldNow: root.notificationService ? Number(root.notificationService.heldCount || 0) : 0

  readonly property string tooltip: {
    if (root.dndOn) return "DND on — right-click to turn off"
    if (root.autoDnd) return "Holding notifications (" + root.autoDndText + ")"
      + (root.heldNow > 0 ? " · " + root.heldNow + " held" : "")
    if (root.digestVisible) return root.digestShown + " held while you were busy"
    return root.liveCount > 0 ? root.liveCount + " live notifications" : "Notification Center"
  }

  // Same roles as the stock notification panel. Reading popups.text directly
  // throws while the singleton is still coming up and the binding then stays
  // on black, so missing roles fall through to the base palette.
  readonly property color colForeground: {
    var popups = Commons.Color.popups
    if (popups && popups.text !== undefined && popups.text !== null)
      return popups.text
    var fallback = Commons.Color.foreground
    return (fallback !== undefined && fallback !== null) ? fallback : "#a9b1d6"
  }
  readonly property color colDim: Qt.darker(colForeground, 1.4)
  readonly property color colAccent: {
    var value = Commons.Color.accent
    return (value !== undefined && value !== null) ? value : "#7aa2f7"
  }
  readonly property color colPopupBg: {
    var popups = Commons.Color.popups
    if (popups && popups.background !== undefined && popups.background !== null)
      return popups.background
    var fallback = Commons.Color.background
    return (fallback !== undefined && fallback !== null) ? fallback : "#1a1b26"
  }
  readonly property int cardRadius: notificationService && notificationService.cornerRadius
    ? notificationService.cornerRadius : Style.cornerRadius

  function notificationIconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  function formatTimestamp(ms) {
    var date = new Date(Number(ms) || Date.now())
    var now = new Date()
    var sameDay = date.getFullYear() === now.getFullYear()
      && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
    var time = date.toLocaleTimeString(Qt.locale(), "hh:mm")
    return sameDay ? time : date.toLocaleDateString(Qt.locale(), "MMM d") + " · " + time
  }

  function rowMatches(row) {
    var needle = root.query.trim().toLowerCase()
    if (needle === "") return true
    var haystack = [row.app, row.herdrSpace, row.summary, row.body].join(" ").toLowerCase()
    return haystack.indexOf(needle) >= 0
  }

  // How many notifications the list shows, headers aside.
  property int matchCount: 0

  function rebuildRows() {
    var rows = []
    for (var h = 0; h < root.historyRows.length; ++h) {
      var history = root.historyRows[h]
      if (root.hiddenHistoryKeys[root.historyKey(history)]) continue
      if (!rowMatches(history)) continue
      rows.push({
        isHeader: false,
        sourceIndex: -1,
        isLive: false,
        id: history.id,
        originalId: history.originalId,
        app: history.app,
        appIcon: history.appIcon,
        summary: history.summary,
        body: history.body,
        glyph: history.glyph,
        herdrPane: history.herdrPane,
        herdrSpace: history.herdrSpace,
        urgency: history.urgency,
        timestamp: history.timestamp
      })
    }
    var model = root.notificationService ? root.notificationService.popupModel : null
    if (model) {
      for (var i = 0; i < model.count; ++i) {
        var row = model.get(i)
        if (!row || !rowMatches(row)) continue
        var liveSummary = String(row.summary || "").trim()
        var liveBody = String(row.body || "").trim()
        // An empty restored popup is not a message. Showing it as
        // "Unknown application / Notification" hid the inbox.
        if (!liveSummary && !liveBody) continue
        rows.push({
          isHeader: false,
          sourceIndex: i,
          isLive: true,
          id: row.id !== undefined ? row.id : null,
          app: String(row.appName || row.app || "").trim(),
          appIcon: String(row.appIcon || ""),
          summary: liveSummary,
          body: liveBody,
          glyph: String(row.glyph || NotificationLogic.glyphFromHints(row.hints)),
          herdrPane: String(row.herdrPane || ""),
          herdrSpace: String(row.herdrSpace || ""),
          urgency: Number(row.urgency || 1),
          timestamp: Number(row.timestamp || 0),
          actions: root.notificationService.actionsForRow(row)
        })
      }
    }
    rows.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
    root.matchCount = rows.length
    // Herdr rows gather under a header per space. Headers carry the row
    // fields as blanks so the shared delegate's bindings stay defined.
    root.filteredRows = NotificationLogic.groupInboxRows(rows).map(function(entry) {
      if (!entry.isHeader) return entry
      return Object.assign({
        sourceIndex: -1, isLive: false, id: null, app: "", appIcon: "", summary: "",
        body: "", glyph: "", herdrPane: "", herdrSpace: "", urgency: 1, timestamp: 0
      }, entry)
    })
  }

  // A Herdr row opens its pane (through tyler.juice) and leaves the inbox;
  // any other row is dismissed.
  function activate(row) {
    if (!row || row.isHeader) return
    var service = root.notificationService
    if (NotificationLogic.isHerdrApp(row.app) && row.herdrPane && service
        && typeof service.focusHerdrPane === "function" && service.focusHerdrPane(row.herdrPane)) {
      root.dismiss(row)
      root.close()
      return
    }
    root.dismiss(row)
  }

  function dismiss(row) {
    if (!row) return
    if (row.isLive) {
      if (root.notificationService && typeof root.notificationService.dismissPopup === "function")
        root.notificationService.dismissPopup(row.sourceIndex)
    } else {
      var key = root.historyKey(row)
      var next = Object.assign({}, root.hiddenHistoryKeys)
      next[key] = true
      root.hiddenHistoryKeys = next
      if (root.notificationService && typeof root.notificationService.removeHistoryEntry === "function")
        root.notificationService.removeHistoryEntry(row)
    }
    rebuildRows()
  }

  function clearSearch() {
    root.query = ""
    searchField.text = ""
  }

  function clearAll() {
    if (!root.notificationService) return
    if (typeof root.notificationService.clearAllByHand === "function") root.notificationService.clearAllByHand()
    root.historyRows = []
    root.hiddenHistoryKeys = ({})
    rebuildRows()
  }

  // Enough of the inbox to read back through a morning, past the old
  // ten-file cap. The list scrolls once the card hits its height cap.
  readonly property int inboxLimit: 30

  // This plugin's history files, one JSON line each, timestamps in ms.
  function historyTimestamp(value) {
    var ts = Number(value.timestamp || 0)
    return isFinite(ts) && ts > 0 ? ts : 0
  }

  // A row with no title and no message is the blank file left at shell
  // restart. Skip it. An empty app name stays empty so the title and body
  // are what you read, rather than "Unknown application" / "Notification".
  function historyEntryFrom(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null
    var app = String(value.app || value.appName || value.source || "").trim()
    var summary = String(value.summary || "").trim()
    var body = String(value.body || value.rawBody || "").trim()
    if (!summary && !body) return null
    var herdr = NotificationLogic.isHerdrApp(app)
    return {
      id: value.id !== undefined ? value.id : null,
      originalId: value.originalId !== undefined ? value.originalId : 0,
      app: app,
      appIcon: String(value.appIcon || ""),
      summary: summary,
      body: body,
      glyph: String(value.glyph || ""),
      herdrPane: herdr ? NotificationLogic.herdrPaneId(value.herdrPane) : "",
      herdrSpace: herdr ? NotificationLogic.herdrSpaceLabel(value.herdrSpace) : "",
      urgency: Number(value.urgency === undefined ? 1 : value.urgency),
      timestamp: root.historyTimestamp(value)
    }
  }

  function entriesFromLines(raw) {
    var parsed = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; ++i) {
      var line = lines[i].trim()
      if (!line) continue
      try {
        var entry = root.historyEntryFrom(JSON.parse(line))
        if (entry) parsed.push(entry)
      } catch (e) {
        // A torn write is ignored, matching the first-party parser.
      }
    }
    return parsed
  }

  function parseHistory(raw) {
    var parsed = root.entriesFromLines(raw)
    parsed.sort(function(a, b) { return b.timestamp - a.timestamp })
    root.historyRows = parsed.slice(0, root.inboxLimit)
    rebuildRows()
  }

  function refreshHistory() {
    if (!root.historyDir || historyReader.running) return
    historyReader.command = ["bash", "-c",
      "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", root.historyDir]
    historyReader.running = true
  }

  onPopupOpenChanged: {
    // Opening the inbox, and closing it again, is looking at it: what was
    // there stops lighting the chip.
    if (root.notificationService && typeof root.notificationService.markSeen === "function")
      root.notificationService.markSeen()
    if (popupOpen) {
      clearSearch()
      refreshHistory()
      rebuildRows()
    }
  }
  onQueryChanged: rebuildRows()

  Timer {
    interval: 500
    repeat: true
    running: root.popupOpen
    onTriggered: root.refreshHistory()
  }

  Process {
    id: historyReader
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseHistory(text)
    }
  }

  Connections {
    target: root.notificationService ? root.notificationService.popupModel : null
    function onCountChanged() { root.rebuildRows() }
    function onDataChanged() { root.rebuildRows() }
    function onRowsInserted() { root.rebuildRows() }
    function onRowsRemoved() { root.rebuildRows() }
    function onModelReset() { root.rebuildRows() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    // The button still sizes itself from its own (hidden) label; chipLabel
    // draws the same text so it can fade and pulse.
    labelVisible: false
    active: root.lit
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.toggleDnd()
      } else {
        root.popupOpen = !root.popupOpen
      }
    }

    Text {
      id: chipLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.text
      color: root.chipColor
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      renderType: Text.NativeRendering
      rotation: button.textRotation
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      transformOrigin: Item.Center

      // Arrival: fade to accent (urgent for critical). Colour is meaning, so
      // it stays under reduced motion; nothing fades while DND is on.
      Behavior on color {
        enabled: !root.dndOn && (!root.autoDnd || root.unseenCritical > 0)
        ColorAnimation { duration: Motion.settle; easing.type: Easing.OutCubic }
      }
    }

    // Critical arrival: one slow pulse, never a loop.
    SequentialAnimation {
      id: criticalPulse
      NumberAnimation {
        target: chipLabel; property: "scale"; to: 1.28
        duration: Math.round(Motion.pulse * 0.35); easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: chipLabel; property: "scale"; to: 1
        duration: Math.round(Motion.pulse * 0.65); easing.type: Easing.InOutCubic
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: searchField
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(inbox.implicitHeight, Style.space(520))

    ColumnLayout {
      id: inbox
      width: parent.width
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(10)

      // ----------------------------------------- header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: "Notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colForeground
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          text: (root.matchCount === 1 ? "1 notification" : root.matchCount + " notifications")
            + (root.autoDnd && !root.dndOn ? " · holding (" + root.autoDndText + ")" : "")
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colDim
          font.pixelSize: Style.font.caption
        }

        Item { Layout.fillWidth: true }

        BorderSurface {
          id: dndPill
          visible: root.dndSupported
          Layout.preferredHeight: Math.max(Style.space(24), Style.font.bodySmall + Style.spacing.controlPaddingY * 2)
          Layout.preferredWidth: dndLabel.implicitWidth + dndGlyph.implicitWidth + Style.space(18)
          radius: Math.min(Style.space(12), root.cardRadius + Style.space(6))
          color: root.dndOn ? root.colAccent : Style.normalFillFor(root.colForeground, root.colAccent)
          borderSpec: Border.controlSpec(root.dndOn ? "selected" : "normal", root.colForeground, root.colAccent)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              id: dndGlyph
              text: root.dndOn ? "󰂛" : "󰂚"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.dndOn ? root.colPopupBg : root.colDim
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: dndLabel
              text: root.dndOn ? "DND on" : "DND off"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.dndOn ? root.colPopupBg : root.colDim
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleDnd()
          }
        }

        BorderSurface {
          Layout.preferredWidth: Style.space(22)
          Layout.preferredHeight: Style.space(22)
          radius: Math.min(Style.space(6), root.cardRadius)
          color: Style.controlFill(false, closeHeaderArea.containsMouse, root.colForeground, root.colAccent)
          borderSpec: Border.controlSpec(closeHeaderArea.containsMouse ? "hover" : "normal", root.colForeground, root.colAccent)

          Text {
            anchors.centerIn: parent
            text: "󰅖"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colForeground
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: closeHeaderArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
          }
        }
      }

      // ----------------------------------------- search
      Ui.TextField {
        id: searchField
        Layout.fillWidth: true
        foreground: root.colForeground
        accent: root.colAccent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        placeholderText: "Search notifications"
        activeFocusOnPress: true
        onTextEdited: root.query = text
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.query.length > 0) {
              root.clearSearch()
            } else {
              root.close()
            }
            event.accepted = true
          }
        }
      }

      // ----------------------------------------- label + clear all
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          text: root.query.trim() === "" ? "Recent and live notifications" : root.matchCount + " matching notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colDim
          font.pixelSize: Style.font.caption
        }

        BorderSurface {
          Layout.preferredWidth: clearLabel.implicitWidth + Style.space(16)
          Layout.preferredHeight: Math.max(Style.space(22), Style.font.bodySmall + Style.spacing.controlPaddingY * 2)
          radius: Math.min(Style.space(6), root.cardRadius)
          color: Style.controlFill(false, clearArea.containsMouse, root.colForeground, root.colAccent)
          borderSpec: Border.controlSpec(clearArea.containsMouse ? "hover" : "normal", root.colForeground, root.colAccent)

          Text {
            id: clearLabel
            anchors.centerIn: parent
            text: "Clear all"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colForeground
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: clearArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearAll()
          }
        }
      }

      // ----------------------------------------- list
      ListView {
        id: listView
        Layout.fillWidth: true
        Layout.preferredHeight: count > 0 ? Math.min(contentHeight, Style.space(380)) : 0
        clip: true
        spacing: Style.space(8)
        boundsBehavior: Flickable.StopAtBounds
        model: root.filteredRows
        visible: count > 0

        delegate: Item {
          id: rowSlot
          required property var modelData
          readonly property bool isHeader: modelData.isHeader === true
          readonly property bool isHerdr: !isHeader && NotificationLogic.isHerdrApp(modelData.app)

          width: listView.width
          implicitHeight: isHeader ? groupHeader.implicitHeight + Style.space(4) : rowCard.implicitHeight
          height: implicitHeight

          // Herdr space header: the rows under it are that space's agents.
          RowLayout {
            id: groupHeader
            visible: rowSlot.isHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(6)

            Text {
              text: "Herdr"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.colDim
              font.pixelSize: Style.font.caption
            }

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: rowSlot.modelData.label || "Unnamed space"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.colForeground
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              text: String(rowSlot.modelData.count || 0)
              font.family: root.bar ? root.bar.fontFamily : ""
              color: root.colDim
              font.pixelSize: Style.font.caption
            }
          }

          BorderSurface {
            id: rowCard
            readonly property var modelData: rowSlot.modelData
            visible: !rowSlot.isHeader

            readonly property string smallIconSource: root.notificationIconSource(modelData.appIcon)
            readonly property bool hasIcon: modelData.glyph === "" && smallIconSource.length > 0
            readonly property string sanitizedBody: NotificationLogic.sanitizeBody(modelData.body, modelData.app, modelData.appIcon)

            // Herdr rows sit indented under their space header.
            x: rowSlot.isHerdr ? Style.space(10) : 0
            width: rowSlot.width - x
            implicitHeight: rowContent.implicitHeight + Style.spacing.panelGap
            height: implicitHeight
            radius: root.cardRadius
            color: Style.controlFill(false, rowHoverArea.containsMouse, root.colForeground, root.colAccent)
            borderSpec: Border.controlSpec(rowHoverArea.containsMouse ? "hover" : "normal", root.colForeground, root.colAccent)

            // Left click dismisses, or opens the pane for a Herdr row. Hover
            // reveals a dedicated close (x) button that only dismisses.
            MouseArea {
              id: rowHoverArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activate(rowCard.modelData)
            }

            RowLayout {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: rowCard.borderLeft + Style.space(12)
              anchors.rightMargin: rowCard.borderRight + Style.space(12)
              spacing: Style.space(10)

              Text {
                Layout.alignment: Qt.AlignTop
                visible: rowCard.modelData.glyph !== ""
                text: rowCard.modelData.glyph
                color: rowCard.modelData.urgency === 2 ? Commons.Color.urgent : root.colAccent
                font.family: root.bar ? root.bar.fontFamily : ""
                font.pixelSize: Style.font.icon
              }

              Item {
                Layout.preferredWidth: Style.space(32)
                Layout.preferredHeight: Style.space(32)
                Layout.alignment: Qt.AlignVCenter
                visible: rowCard.hasIcon && rowIconImage.status !== Image.Error

                Image {
                  id: rowIconImage
                  anchors.fill: parent
                  source: rowCard.smallIconSource
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  asynchronous: true
                  smooth: true
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                RowLayout {
                  Layout.fillWidth: true
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: rowCard.modelData.app
                    font.family: root.bar ? root.bar.fontFamily : ""
                    color: root.colDim
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Text {
                    text: root.formatTimestamp(rowCard.modelData.timestamp)
                    font.family: root.bar ? root.bar.fontFamily : ""
                    color: root.colDim
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  Layout.fillWidth: true
                  visible: rowCard.modelData.summary.length > 0
                  textFormat: Text.PlainText
                  text: rowCard.modelData.summary
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colForeground
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  maximumLineCount: 2
                }

                Text {
                  Layout.fillWidth: true
                  visible: rowCard.sanitizedBody.length > 0
                  text: rowCard.sanitizedBody
                  textFormat: Text.PlainText
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colForeground
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  maximumLineCount: 8
                }

                NotificationActions {
                  Layout.fillWidth: true
                  foreground: root.colForeground
                  accent: root.colAccent
                  actions: rowCard.modelData.actions || []
                  onInvoked: identifier => root.notificationService.invokeInboxAction(rowCard.modelData, identifier)
                }
              }

              // Close (x): visible ONLY while hovering this row.
              Rectangle {
                Layout.preferredWidth: Style.space(20)
                Layout.preferredHeight: Style.space(20)
                Layout.alignment: Qt.AlignVCenter
                visible: rowHoverArea.containsMouse
                radius: Math.min(4, root.cardRadius)
                color: closeArea.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "✕"
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colDim
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: closeArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    mouse.accepted = true
                    root.dismiss(rowCard.modelData)
                  }
                }
              }
            }
          }
        }
      }

      // ----------------------------------------- empty state
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: listView.count === 0 ? Style.space(96) : 0
        visible: listView.count === 0

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰂚"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colDim
            font.pixelSize: Style.font.displayLarge
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.query.trim() === "" ? "No notifications" : "No matching notifications"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colDim
            font.pixelSize: Style.font.body
          }
        }
      }

      // ----------------------------------------- footer legend
      Text {
        Layout.fillWidth: true
        text: "Click dismisses (a Herdr row opens its pane) · ✕ dismisses · Esc closes"
        font.family: root.bar ? root.bar.fontFamily : ""
        color: root.colDim
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignLeft
      }
    }
  }
}
