import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "MediaModel.js" as MediaModel
import "../tyler.juice/Motion.js" as Motion

// Panel content for tyler.media: cover, title/chapter/artist, seek, transport,
// volume in dB, then Stations / Queue / Sound / Lyrics.
Item {
  id: panel

  property var service: null
  property QtObject bar: null
  property bool active: false
  property bool tintArt: false
  property string tab: "stations"
  signal requestClose()

  readonly property var s: service
  readonly property bool connected: s ? s.connected : false
  readonly property bool reduced: s ? s.reducedMotion : false
  readonly property string status: s ? s.status : "absent"
  readonly property color fg: Color.popups.text
  readonly property color muted: Util.alpha(fg, 0.62)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function glyph(cp) { return String.fromCodePoint(cp) }

  implicitHeight: column.implicitHeight

  function syncLyricsWanted() {
    if (s) s.lyricsWanted = active && tab === "lyrics"
  }
  onActiveChanged: syncLyricsWanted()
  onTabChanged: {
    syncLyricsWanted()
    if (tab === "queue" && s) s.refreshQueue()
    body.contentY = 0
  }
  onServiceChanged: syncLyricsWanted()

  readonly property int playlistRevision: s ? s.snap.playlistRevision : 0
  onPlaylistRevisionChanged: if (active && s) s.refreshQueue()

  readonly property string stateLine: {
    if (!s) return ""
    switch (status) {
    case "error": return s.errorText
    case "absent": return "cliamp isn't running"
    case "starting": return "Starting cliamp\u2026"
    case "working": return s.pendingAction === "pause" || s.pendingAction === "sleep" ? "Pausing\u2026" : "Waiting for cliamp\u2026"
    case "buffering": return "Buffering\u2026"
    case "paused": return "Paused" + playlistSuffix
    case "stopped": return "Stopped" + playlistSuffix
    default: return "Playing" + playlistSuffix
    }
  }
  readonly property string playlistSuffix: {
    var name = s ? (s.loadedPlaylist || s.configPlaylist) : ""
    return name ? " \u00b7 " + name : ""
  }
  readonly property color stateColor: status === "error" ? Color.urgent
    : (status === "buffering" || status === "playing") ? Color.accent : muted

  // ------------------------------------------------------------ components

  component SectionHeader: PanelSectionHeader {
    foreground: panel.fg
    fontFamily: panel.fontFamily
    width: parent ? parent.width : 0
    topPadding: Style.space(8)
    bottomPadding: Style.space(2)
  }

  component IconAction: Text {
    id: action
    property int codepoint: 0
    property string tip: ""
    property bool lit: false
    signal activated()
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    textFormat: Text.PlainText
    text: String.fromCodePoint(codepoint)
    color: lit ? Color.accent : (actionMouse.containsMouse ? panel.fg : panel.muted)
    font.family: panel.fontFamily
    font.pixelSize: Style.font.body
    leftPadding: Style.space(4)
    rightPadding: Style.space(4)
    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.activated()
    }
    PanelToolTip {
      visible: actionMouse.containsMouse && action.tip !== ""
      text: action.tip
    }
  }

  component ListRow: BorderSurface {
    id: row
    property int codepoint: 0x0F387
    property string label: ""
    property string detail: ""
    property bool current: false
    property bool canPlayNext: false
    property bool canPin: false
    property bool pinned: false
    property bool removable: false
    property bool clickable: true
    signal activated()
    signal playNext()
    signal pin()
    signal remove()

    width: parent ? parent.width : 0
    height: Math.max(Style.spacing.popupRowHeight, labels.implicitHeight + Style.space(8))
    radius: Style.spacing.labelGap
    color: current ? Style.selectedFillFor(panel.fg, Color.accent)
      : (rowHover.hovered && clickable ? Style.hoverFillFor(panel.fg, Color.accent) : "transparent")

    HoverHandler { id: rowHover }

    MouseArea {
      anchors.fill: parent
      enabled: row.clickable
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activated()
    }

    Text {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: String.fromCodePoint(row.codepoint)
      color: row.current ? Color.accent : panel.muted
      font.family: panel.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      id: labels
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.space(6)
      anchors.right: actions.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.label
        color: panel.fg
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: row.current
        elide: Text.ElideRight
        maximumLineCount: 1
      }
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: row.detail
        color: panel.muted
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      IconAction {
        visible: row.canPlayNext && rowHover.hovered
        codepoint: 0xF0412
        tip: "Play next"
        onActivated: row.playNext()
      }
      IconAction {
        visible: row.canPin && (rowHover.hovered || row.pinned)
        codepoint: 0xF04FE
        lit: row.pinned
        tip: row.pinned ? "Focus station (click to unpin)" : "Use as focus station"
        onActivated: row.pin()
      }
      IconAction {
        visible: row.removable && rowHover.hovered
        codepoint: 0xF0156
        tip: "Remove"
        onActivated: row.remove()
      }
    }
  }

  component TransportButton: Button {
    property int codepoint: 0
    iconText: String.fromCodePoint(codepoint)
    foreground: panel.fg
    fontFamily: panel.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY
    opacity: enabled ? 1 : 0.4
  }

  function trackStation(t) {
    return { kind: "track", path: t.path, title: t.title, artist: t.artist, stream: t.stream, realtime: t.realtime }
  }

  // ------------------------------------------------------------ layout

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // Cover, title, state.
    Item {
      width: parent.width
      height: Math.max(art.height, info.implicitHeight)

      BorderSurface {
        id: art
        width: Style.space(76)
        height: width
        radius: Style.spacing.labelGap
        color: Style.normalFillFor(panel.fg, Color.accent)
        borderSpec: Border.controlSpec("normal", panel.fg, Color.accent)
        clip: true

        Image {
          id: cover
          anchors.fill: parent
          anchors.margins: Style.space(2)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          sourceSize.width: 320
          source: panel.s ? panel.s.artSource : ""
          visible: status === Image.Ready && !tint.visible
        }

        // Optional theme tint: the thumbnail recoloured toward the accent.
        MultiEffect {
          id: tint
          anchors.fill: cover
          source: cover
          visible: panel.tintArt && cover.status === Image.Ready
          colorization: 0.55
          colorizationColor: Color.accent
        }

        Text {
          anchors.centerIn: parent
          visible: cover.status !== Image.Ready
          textFormat: Text.PlainText
          text: panel.glyph(0xF075A)
          color: panel.muted
          font.family: panel.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Column {
        id: info
        anchors.left: art.right
        anchors.leftMargin: Style.space(12)
        anchors.right: showPlayer.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: panel.s && panel.s.title ? panel.s.title : "Nothing playing"
          color: panel.fg
          font.family: panel.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: panel.s ? panel.s.subtitle : ""
          color: panel.muted
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          maximumLineCount: 1
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: panel.stateLine
          color: panel.stateColor
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }

      TransportButton {
        id: showPlayer
        anchors.top: parent.top
        anchors.right: parent.right
        codepoint: 0xF0140
        tooltipText: "Show cliamp as a drop-down"
        horizontalPadding: Style.space(6)
        verticalPadding: Style.space(4)
        onClicked: {
          panel.s.showPlayer()
          panel.requestClose()
        }
      }
    }

    // Seek, with chapter marks.
    Column {
      width: parent.width
      spacing: Style.space(3)
      visible: panel.connected && !!panel.s.track

      Item {
        width: parent.width
        height: Math.round(Style.spacing.controlHeight * 0.7)
        visible: panel.s && panel.s.hasProgress

        Repeater {
          model: panel.s && panel.s.hasProgress ? panel.s.chapters : []
          Rectangle {
            required property var modelData
            width: Math.max(1, Style.space(1))
            height: Math.round(parent.height * 0.6)
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * Math.min(1, modelData.start / Math.max(1, panel.s.snap.duration))
            color: panel.muted
            opacity: 0.6
          }
        }

        PanelSlider {
          anchors.fill: parent
          bar: panel.bar
          minimum: 0
          maximum: Math.max(1, panel.s ? panel.s.snap.duration : 1)
          step: 1
          value: panel.s ? panel.s.position : 0
          enabled: panel.s && panel.s.snap.seekable
          onReleased: function(value) { panel.s.seekTo(value, "seek") }
        }
      }

      Item {
        width: parent.width
        height: elapsed.implicitHeight

        Text {
          id: elapsed
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: !panel.s ? "" : panel.s.hasProgress ? MediaModel.formatTime(panel.s.position)
            : (panel.s.track && panel.s.track.realtime ? "Live stream" : "")
          color: panel.muted
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: panel.s && !!panel.s.chapter
          textFormat: Text.PlainText
          text: !panel.s || !panel.s.chapter ? "" : "Chapter " + (panel.s.chapterIndex + 1) + " of "
            + panel.s.chapters.length + " \u00b7 "
            + MediaModel.formatTime(panel.s.position - panel.s.chapter.start)
            + (panel.s.chapter.end > panel.s.chapter.start
              ? " / " + MediaModel.formatTime(panel.s.chapter.end - panel.s.chapter.start) : "")
          color: panel.muted
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          visible: panel.s && panel.s.hasProgress
          textFormat: Text.PlainText
          text: panel.s ? MediaModel.formatTime(panel.s.snap.duration) : ""
          color: panel.muted
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // Transport. Previous/next follow chapters in a mix; the outer pair always
    // moves between playlist items.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(4)

      TransportButton {
        codepoint: 0xF0F28
        tooltipText: "Previous item"
        enabled: panel.connected
        onClicked: panel.s.previousItem()
      }
      TransportButton {
        codepoint: 0xF04AE
        tooltipText: panel.s && panel.s.chapters.length ? "Previous chapter" : "Previous"
        enabled: panel.connected
        onClicked: panel.s.previous(false)
      }
      TransportButton {
        readonly property bool busy: panel.status === "buffering" || panel.status === "starting"
        codepoint: busy ? 0xF0772 : (panel.s && panel.s.targetState === "playing" ? 0xF03E4 : 0xF040A)
        iconSpinning: busy && !panel.reduced
        iconSize: Style.font.iconLarge
        horizontalPadding: Style.spacing.panelGap
        tooltipText: panel.status === "absent" ? "Start the focus station" : "Play or pause (fades)"
        enabled: panel.status !== "starting"
        onClicked: panel.s.togglePlay(false)
      }
      TransportButton {
        codepoint: 0xF04AD
        tooltipText: panel.s && panel.s.chapters.length ? "Next chapter" : "Next"
        enabled: panel.connected
        onClicked: panel.s.next(false)
      }
      TransportButton {
        codepoint: 0xF0F27
        tooltipText: "Next item"
        enabled: panel.connected
        onClicked: panel.s.nextItem()
      }
    }

    // Volume in dB.
    Item {
      width: parent.width
      height: Math.round(Style.spacing.controlHeight * 0.8)
      visible: panel.connected

      Text {
        id: volumeIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(20)
        textFormat: Text.PlainText
        text: MediaModel.volumeGlyph(panel.s ? panel.s.volume : 0)
        color: panel.muted
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
      }
      PanelSlider {
        anchors.left: volumeIcon.right
        anchors.right: volumeLabel.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        bar: panel.bar
        minimum: MediaModel.minVolume
        maximum: MediaModel.maxVolume
        step: 1
        integer: true
        value: panel.s ? panel.s.volume : 0
        onMoved: function(value) { panel.s.setVolume(value) }
        onReleased: function(value) { panel.s.setVolume(value) }
      }
      Text {
        id: volumeLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(52)
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: MediaModel.formatDb(panel.s ? panel.s.volume : 0)
        color: panel.fg
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSeparator { foreground: panel.fg; width: parent.width }

    ButtonGroup {
      anchors.horizontalCenter: parent.horizontalCenter
      options: [
        { value: "stations", label: "Stations" },
        { value: "queue", label: "Queue" },
        { value: "sound", label: "Sound" },
        { value: "lyrics", label: "Lyrics" }
      ]
      value: panel.tab
      foreground: panel.fg
      fontFamily: panel.fontFamily
      fontSize: Style.font.bodySmall
      focusable: false
      onChanged: function(value) { panel.tab = value }
    }

    Flickable {
      id: body
      width: parent.width
      height: Math.min(bodyContent.implicitHeight, Style.space(300))
      contentWidth: width
      contentHeight: bodyContent.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      NumberAnimation {
        id: scrollAnimation
        target: body
        property: "contentY"
        duration: panel.reduced ? 0 : Motion.settle
        easing.type: Easing.InOutCubic
      }

      Column {
        id: bodyContent
        width: body.width
        spacing: Style.space(2)

        // ---------------- stations
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: panel.tab === "stations"

          ListRow {
            readonly property var session: panel.s ? panel.s.saved.lastSession : null
            visible: !!session && !(panel.s.playing && panel.s.trackPath === session.path)
            codepoint: 0xF099B
            label: session ? "Resume " + (session.title || MediaModel.basename(session.path)) : ""
            detail: !session ? "" : [session.position > 20 ? "from " + MediaModel.formatTime(session.position) : "",
              session.playlist || ""].filter(function(x) { return x !== "" }).join(" \u00b7 ")
            onActivated: panel.s.resumeLast()
          }

          SectionHeader { text: "Playlists"; visible: panel.s && panel.s.playlists.length > 0 }
          Repeater {
            model: panel.s ? panel.s.playlists : []
            ListRow {
              required property var modelData
              readonly property var station: ({ kind: "playlist", name: modelData })
              codepoint: 0xF0CB8
              label: modelData
              current: panel.connected && panel.s.loadedPlaylist === modelData
              canPin: true
              pinned: panel.s.isFocusStation(station)
              onActivated: panel.s.playPlaylist(modelData)
              onPin: panel.s.toggleFocusStation(station)
            }
          }

          SectionHeader { text: "Radio"; visible: panel.s && panel.s.radios.length > 0 }
          Repeater {
            model: panel.s ? panel.s.radios : []
            ListRow {
              required property var modelData
              codepoint: 0xF0439
              label: modelData.title
              detail: modelData.artist
              current: panel.s.trackPath === modelData.path
              canPlayNext: panel.connected
              canPin: true
              pinned: panel.s.isFocusStation(panel.trackStation(modelData))
              onActivated: panel.s.playTrack(modelData)
              onPlayNext: panel.s.playNextTrack(modelData)
              onPin: panel.s.toggleFocusStation(panel.trackStation(modelData))
            }
          }

          SectionHeader { text: "Favourites"; visible: panel.s && panel.s.favourites.length > 0 }
          Repeater {
            model: panel.s ? panel.s.favourites : []
            ListRow {
              required property var modelData
              codepoint: 0xF02D1
              label: modelData.title
              detail: modelData.artist
              current: panel.s.trackPath === modelData.path
              canPlayNext: panel.connected
              canPin: true
              pinned: panel.s.isFocusStation(panel.trackStation(modelData))
              onActivated: panel.s.playTrack(modelData)
              onPlayNext: panel.s.playNextTrack(modelData)
              onPin: panel.s.toggleFocusStation(panel.trackStation(modelData))
            }
          }

          SectionHeader { text: "Recent"; visible: panel.s && panel.s.history.length > 0 }
          Repeater {
            model: panel.s ? panel.s.history : []
            ListRow {
              required property var modelData
              codepoint: 0xF02DA
              label: modelData.title
              detail: modelData.artist
              current: panel.s.trackPath === modelData.path
              canPlayNext: panel.connected
              canPin: true
              pinned: panel.s.isFocusStation(panel.trackStation(modelData))
              onActivated: panel.s.playTrack(modelData)
              onPlayNext: panel.s.playNextTrack(modelData)
              onPin: panel.s.toggleFocusStation(panel.trackStation(modelData))
            }
          }

          Text {
            width: parent.width
            topPadding: Style.space(6)
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: "The pinned station is what focus mode starts when nothing is playing."
            color: panel.muted
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------------- queue
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: panel.tab === "queue"

          Text {
            visible: !panel.connected
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: "Start cliamp to see its queue."
            color: panel.muted
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          SectionHeader { text: "Up next"; visible: panel.connected && panel.s.playNextItems.length > 0 }
          Repeater {
            model: panel.connected ? panel.s.playNextItems : []
            ListRow {
              required property var modelData
              codepoint: 0xF0411
              label: MediaModel.trackTitle(modelData)
              detail: modelData.artist
              clickable: false
              removable: true
              onRemove: panel.s.removePlayNext(modelData.index)
            }
          }

          SectionHeader {
            text: "Playlist" + (panel.s && panel.s.loadedPlaylist ? " \u00b7 " + panel.s.loadedPlaylist : "")
            visible: panel.connected && panel.s.queueItems.length > 0
          }
          Repeater {
            model: panel.connected ? panel.s.queueItems : []
            ListRow {
              required property var modelData
              readonly property bool playingHere: modelData.index === panel.s.snap.index
              codepoint: playingHere ? 0xF040A : 0xF0387
              label: MediaModel.trackTitle(modelData)
              detail: modelData.artist
              current: playingHere
              canPlayNext: !playingHere
              onActivated: panel.s.queuePlay(modelData.index)
              onPlayNext: panel.s.queueEnqueue(modelData.index)
            }
          }
        }

        // ---------------- sound
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: panel.tab === "sound"

          SectionHeader { text: "Equaliser" }
          Flow {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: panel.s ? panel.s.eqPresets.concat(panel.s.saved.customBands ? ["Custom"] : []) : []
              Button {
                required property var modelData
                text: modelData
                selected: panel.connected && panel.s.snap.eqPreset === modelData
                enabled: panel.connected
                opacity: enabled ? 1 : 0.4
                bordered: true
                foreground: panel.fg
                fontFamily: panel.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                tooltipText: modelData === "Custom" ? "Your own bands, as last set in cliamp" : ""
                onClicked: modelData === "Custom" ? panel.s.restoreCustomEq() : panel.s.setEqPreset(modelData)
              }
            }
          }

          SectionHeader { text: "Sleep timer" }
          Flow {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: [15, 30, 45, 60, 90]
              Button {
                required property var modelData
                text: modelData + " min"
                bordered: true
                foreground: panel.fg
                fontFamily: panel.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: panel.s.setSleep(modelData)
              }
            }
            Button {
              visible: panel.s && panel.s.sleepEndsAt > 0
              text: "Off"
              bordered: true
              foreground: panel.fg
              fontFamily: panel.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: panel.s.cancelSleep()
            }
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: !panel.s ? "" : panel.s.sleepEndsAt > 0
              ? "Pauses in " + MediaModel.formatRemaining(panel.s.sleepRemainingMs)
                + (panel.s.sleepFading ? " \u00b7 fading out" : " \u00b7 fades out over the final minute")
              : "Pauses the music later, fading out over the final minute."
            color: panel.s && panel.s.sleepEndsAt > 0 ? Color.accent : panel.muted
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------------- lyrics
        Column {
          id: lyricsColumn
          width: parent.width
          spacing: Style.space(3)
          visible: panel.tab === "lyrics"

          readonly property var lyrics: panel.s ? panel.s.lyrics : null
          readonly property int currentLine: {
            if (!lyrics || !lyrics.synced || !panel.s) return -1
            var t = panel.s.position - lyrics.offset
            var index = -1
            for (var i = 0; i < lyrics.lines.length; i++) {
              if (lyrics.lines[i].start <= t + 0.3) index = i
              else break
            }
            return index
          }
          onCurrentLineChanged: {
            if (currentLine < 0 || !panel.active || panel.tab !== "lyrics") return
            var item = lyricsRepeater.itemAt(currentLine)
            if (!item) return
            var target = lyricsColumn.y + item.y - body.height / 3
            target = Math.max(0, Math.min(target, body.contentHeight - body.height))
            scrollAnimation.stop()
            scrollAnimation.to = target
            scrollAnimation.start()
          }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            visible: text !== ""
            text: {
              var l = lyricsColumn.lyrics
              if (!panel.s || !panel.s.trackPath) return "Nothing playing."
              if (!l || l.state === "idle" || l.state === "loading") return "Looking for lyrics\u2026"
              if (l.state === "none") return "No lyrics found for this track."
              return ""
            }
            color: panel.muted
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            id: lyricsRepeater
            model: lyricsColumn.lyrics && lyricsColumn.lyrics.state === "ok" ? lyricsColumn.lyrics.lines : []
            Text {
              required property var modelData
              required property int index
              readonly property bool now: index === lyricsColumn.currentLine
              width: lyricsColumn.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: modelData.text === "" ? " " : modelData.text
              color: now || !lyricsColumn.lyrics.synced ? panel.fg : panel.muted
              font.family: panel.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: now
            }
          }
        }
      }
    }
  }
}
