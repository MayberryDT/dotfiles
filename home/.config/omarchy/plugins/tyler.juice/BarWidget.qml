import QtQuick
import qs.Commons
import qs.Ui
import "ServiceBridge.js" as ServiceBridge
import "Motion.js" as Motion

// Agent marks (one per Herdr agent that is not idle) and the focus button.
// Shapes carry the meaning so any theme reads: ● working, ◆ blocked,
// ○ finished while unseen, · unknown. Idle agents take no space.
BarWidget {
  id: root
  moduleName: "tyler.juice"
  property var service: null
  readonly property bool reduced: service ? service.motion === "reduced" : false
  readonly property var agents: {
    if (!service || !service.herd || !service.herd.available) return []
    var list = []
    var agentsIn = service.herd.agents || []
    for (var i = 0; i < agentsIn.length; i++) if (agentsIn[i].status !== "idle") list.push(agentsIn[i])
    var rank = { blocked: 0, done: 1, working: 2, unknown: 3 }
    list.sort(function(a, b) { return (rank[a.status] - rank[b.status]) || String(a.space).localeCompare(String(b.space)) })
    return list
  }
  // Panes that already had their one "blocked" pulse.
  property var pulsed: ({})

  // Keep delegates alive across updates so a working breath never restarts
  // and a blocked pulse plays once.
  ListModel { id: agentModel }
  onAgentsChanged: syncAgents()

  function syncAgents() {
    var list = agents
    var sameOrder = agentModel.count === list.length
    for (var i = 0; sameOrder && i < list.length; i++)
      if (agentModel.get(i).pane !== list[i].pane) sameOrder = false
    if (!sameOrder) agentModel.clear()
    var live = {}
    for (var j = 0; j < list.length; j++) {
      var a = list[j]
      live[a.pane] = true
      var row = { pane: a.pane, status: a.status, space: a.space || "", title: a.title || "" }
      if (sameOrder) {
        for (var key in row) if (agentModel.get(j)[key] !== row[key]) agentModel.setProperty(j, key, row[key])
      } else {
        agentModel.append(row)
      }
    }
    var keep = {}
    for (var p in pulsed) if (live[p] && pulsed[p]) keep[p] = true
    pulsed = keep
  }

  function takePulse(pane) {
    if (pulsed[pane]) return false
    var next = Object.assign({}, pulsed)
    next[pane] = true
    pulsed = next
    return true
  }

  function releasePulse(pane) {
    if (!pulsed[pane]) return
    var next = Object.assign({}, pulsed)
    delete next[pane]
    pulsed = next
  }

  readonly property bool focusOn: service ? service.focusOn : false
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.42)
  readonly property string fontFamily: bar ? bar.fontFamily : ""

  // Remaining focus time, refreshed while a timed session runs.
  property double now: Date.now()
  readonly property int minutesLeft: service && focusOn && service.focusEndsAt > 0
    ? Math.max(0, Math.ceil((service.focusEndsAt - now) / 60000)) : 0
  readonly property real focusProgress: service && focusOn && service.focusEndsAt > 0
    ? Math.min(1, Math.max(0, (now - service.focusSince) / (service.focusEndsAt - service.focusSince))) : 0

  readonly property var timerSteps: [25, 50, 90, 0]

  implicitWidth: vertical ? barSize : row.implicitWidth + Style.space(8)
  implicitHeight: vertical ? column.implicitHeight + Style.space(8) : barSize

  function resolveService() {
    var next = ServiceBridge.current()
    if (next !== service) service = next
  }

  function nextTimer() {
    if (!service) return
    var current = focusOn ? service.focusMinutes : -1
    var index = timerSteps.indexOf(current)
    service.startFocus(timerSteps[(index + 1) % timerSteps.length])
  }

  function agentTooltip(agent) {
    var verb = { working: "working", blocked: "needs you", done: "finished", unknown: "status unclear" }[agent.status] || agent.status
    return agent.space + " · " + verb + (agent.title ? "\n" + agent.title : "")
  }

  function focusTooltip() {
    var lines = []
    if (focusOn) lines.push(minutesLeft > 0 ? "Focus on · " + minutesLeft + " min left" : "Focus on")
    else lines.push("Focus mode")
    lines.push(service && service.focusScope === "space"
      ? "Only the current Herdr space can reach you" : "Blocked agents still reach you")
    lines.push("Click: toggle · Middle: 25/50/90 min timer · Right: narrow to current space")
    return lines.join("\n")
  }

  Component.onCompleted: resolveService()
  Timer {
    interval: 250
    repeat: true
    running: !root.service
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }
  Timer {
    interval: 15000
    repeat: true
    running: root.focusOn && root.service && root.service.focusEndsAt > 0
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  // ---------- one agent mark ----------
  component AgentMark: Item {
    id: mark
    required property string pane
    required property string status
    required property string space
    required property string title
    readonly property var agent: ({ pane: pane, status: status, space: space, title: title })
    readonly property string glyph: ({ working: "●", blocked: "◆", done: "○", unknown: "·" })[status] || "·"
    readonly property color tone: status === "blocked" ? Color.urgent
      : status === "done" ? Color.accent
      : status === "working" ? root.fg : root.muted

    implicitWidth: Style.space(14)
    implicitHeight: Style.space(16)

    function maybePulse() {
      if (status !== "blocked") { root.releasePulse(pane); return }
      if (root.takePulse(pane) && !root.reduced) arrivePulse.restart()
    }
    Component.onCompleted: maybePulse()
    onStatusChanged: maybePulse()

    Text {
      id: markText
      anchors.centerIn: parent
      text: mark.glyph
      color: mark.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      opacity: 1

      Behavior on color { ColorAnimation { duration: Motion.duration(Motion.settle, root.service ? root.service.motion : "full") } }

      // A working agent breathes slowly; nothing else moves at rest.
      SequentialAnimation on opacity {
        id: breath
        running: mark.status === "working" && !root.reduced
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: Motion.breathe; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: Motion.breathe; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) markText.opacity = 1
      }
    }

    // A newly blocked agent gets one slow pulse, never a loop.
    SequentialAnimation {
      id: arrivePulse
      NumberAnimation { target: markText; property: "scale"; from: 1; to: 1.5; duration: Motion.pulse / 2; easing.type: Easing.OutCubic }
      NumberAnimation { target: markText; property: "scale"; to: 1; duration: Motion.pulse / 2; easing.type: Easing.InOutCubic }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (root.service) root.service.herdFocus(mark.pane)
      onEntered: if (root.bar) root.bar.showTooltip(mark, root.agentTooltip(mark.agent))
      onExited: if (root.bar) root.bar.hideTooltip(mark)
    }
  }

  // ---------- focus button ----------
  component FocusMark: Item {
    id: focusMark
    implicitWidth: Math.max(Style.space(18), focusRow.implicitWidth + Style.space(6))
    implicitHeight: Style.space(18)

    Row {
      id: focusRow
      anchors.centerIn: parent
      spacing: Style.space(3)

      Text {
        id: focusGlyph
        text: root.focusOn ? "◉" : "◎"
        color: root.focusOn ? Color.accent : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        Behavior on color { ColorAnimation { duration: Motion.duration(Motion.settle, root.service ? root.service.motion : "full") } }
      }

      Text {
        visible: root.focusOn && root.minutesLeft > 0 && !root.vertical
        text: String(root.minutesLeft)
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Timed sessions: a hairline under the mark fills as time passes.
    Rectangle {
      visible: root.focusOn && root.focusProgress > 0
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      height: Math.max(1, Style.space(1))
      width: parent.width * root.focusProgress
      color: Color.accent
      opacity: 0.8
      Behavior on width { NumberAnimation { duration: Motion.duration(Motion.settle, root.service ? root.service.motion : "full") } }
    }

    // Press acknowledged at once.
    scale: focusArea.pressed ? 0.88 : 1
    Behavior on scale { NumberAnimation { duration: Motion.duration(Motion.ack, root.service ? root.service.motion : "full"); easing.type: Easing.OutCubic } }

    MouseArea {
      id: focusArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (!root.service) return
        if (mouse.button === Qt.RightButton) root.service.cycleFocusScope()
        else if (mouse.button === Qt.MiddleButton) root.nextTimer()
        else root.service.focusToggle()
        if (root.bar) root.bar.showTooltip(focusMark, root.focusTooltip())
      }
      onEntered: if (root.bar) root.bar.showTooltip(focusMark, root.focusTooltip())
      onExited: if (root.bar) root.bar.hideTooltip(focusMark)
    }
  }

  // ---------- welcome back ----------
  // Shown once as a tooltip under the marks so nothing in the bar shifts.
  Timer {
    id: welcomeHide
    interval: 6000
    onTriggered: if (root.bar) root.bar.hideTooltip(root)
  }

  Connections {
    target: root.service
    function onWelcomeChanged() {
      var w = root.service.welcome
      if (!w || Date.now() - w.at > 10000 || !root.bar) return
      root.bar.showTooltip(root, "While you were away: " + w.text)
      welcomeHide.restart()
    }
  }

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)

    Repeater {
      model: root.vertical ? 0 : agentModel
      AgentMark { anchors.verticalCenter: parent ? parent.verticalCenter : undefined }
    }
    FocusMark { anchors.verticalCenter: parent.verticalCenter }
  }

  Column {
    id: column
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)

    Repeater {
      model: root.vertical ? agentModel : 0
      AgentMark { anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined }
    }
    FocusMark { anchors.horizontalCenter: parent.horizontalCenter }
  }
}
