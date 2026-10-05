import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "MediaModel.js" as MediaModel
import "ServiceBridge.js" as ServiceBridge

// Singleton owner of everything cliamp for tyler.media. It follows cliamp's
// own v2 event stream, submits actions as v2 jobs and confirms them against
// fresh runtime snapshots, so the bar can show working, buffering and error
// states instead of trusting a fire-and-forget click. Browsers are ignored.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string binDir: home + "/.local/bin"
  readonly property string launcher: binDir + "/juice-media"
  readonly property string cliampDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/cliamp"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/tyler-media"
  readonly property string busPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tyler-juice/state.json"

  // ---------------------------------------------------------------- link

  property string link: "absent"          // absent | starting | connected
  property double startDeadline: 0
  property var snap: MediaModel.emptySnapshot()
  property var whenConnected: []
  property var whenPlaying: []

  readonly property bool connected: link === "connected"
  readonly property bool playing: connected && snap.state === "playing"
  readonly property var track: snap.track || snap.logical
  readonly property string trackPath: track ? track.path : ""

  // Position: snapshots carry a position at a moment; interpolate between them.
  property real posBase: 0
  property double posAt: 0
  property double nowMs: Date.now()
  readonly property real position: {
    var p = posBase
    if (playing && !buffering) p += Math.max(0, nowMs - posAt) / 1000 * snap.speed
    return snap.duration > 0 ? Math.min(p, snap.duration) : p
  }

  // ---------------------------------------------------------------- track metadata

  property string metaPath: ""
  property var chapters: []
  property string artPath: ""
  readonly property int chapterIndex: chapters.length ? MediaModel.chapterIndexAt(chapters, position) : -1
  readonly property var chapter: chapterIndex >= 0 ? chapters[chapterIndex] : null
  readonly property string trackTitle: MediaModel.trackTitle(track)
  readonly property string title: chapter && chapter.title ? chapter.title : trackTitle
  readonly property string subtitle: {
    if (!track) return ""
    if (chapter) return track.title + (track.artist ? " \u00b7 " + track.artist : "")
    if (track.stream && track.streamTitle) return track.station || track.title
    return track.artist
  }
  readonly property string artSource: artPath ? "file://" + artPath : (track && track.artUrl ? track.artUrl : "")
  readonly property bool hasProgress: connected && !!track && !track.realtime && snap.duration > 0
  readonly property real progress: {
    if (!hasProgress) return 0
    if (chapter) {
      var end = chapter.end > chapter.start ? chapter.end : snap.duration
      return Math.max(0, Math.min(1, (position - chapter.start) / Math.max(1, end - chapter.start)))
    }
    return Math.max(0, Math.min(1, position / snap.duration))
  }

  // ---------------------------------------------------------------- pending actions

  // { action, kind: audio|seek|paused, jobDone, deadline, fromPath, fromIndex,
  //   fromPos, requireChange, target, lastPos, lastPath, osd, onConfirm }
  property var pending: null
  property bool buffering: false
  property var freshMark: null
  property string errorText: ""
  readonly property string pendingAction: pending ? pending.action : ""
  // The state a press is heading for, shown the instant it is acknowledged.
  readonly property string targetState: pending
    ? (pending.kind === "paused" ? "paused" : "playing") : snap.state
  readonly property string status: {
    if (errorText) return "error"
    if (link === "absent") return "absent"
    if (link === "starting") return "starting"
    if (pending && !pending.jobDone) return "working"
    if (pending && pending.kind === "paused") return "working"
    if (pending || buffering) return "buffering"
    return snap.state
  }

  // ---------------------------------------------------------------- volume

  property real volume: 0                // resting volume the user chose
  property real wantedVolume: NaN
  property real lastSentVolume: NaN
  property bool volumeInFlight: false
  property double volumeHoldUntil: 0
  property var ramp: null
  property real fadeBase: NaN            // resting volume while a fade is under way
  readonly property bool fading: ramp !== null || !isNaN(fadeBase)

  // ---------------------------------------------------------------- library

  property string loadedPlaylist: ""
  property string configPlaylist: ""
  property var playlists: []
  property var radios: []
  property var favourites: []
  property var history: []
  property var queueItems: []
  property var playNextItems: []
  property var lyrics: ({ key: "", state: "idle", synced: false, offset: 0, lines: [] })
  property var lyricsCache: ({})
  property bool lyricsWanted: false
  readonly property string lyricsKey: trackPath ? trackPath + "#" + chapterIndex : ""
  readonly property var eqPresets: ["Flat", "Rock", "Pop", "Jazz", "Classical", "Bass Boost",
    "Treble Boost", "Vocal", "Electronic", "Acoustic", "Hip-Hop", "R&B", "Loudness",
    "Late Night", "Podcast", "Small Speakers"]

  // ---------------------------------------------------------------- persisted state

  property var saved: ({ lastSession: null, focusStation: null, customBands: null, fadeRestore: null })
  property bool savedLoaded: false
  property int sessionTicks: 0

  // ---------------------------------------------------------------- sleep timer

  property double sleepEndsAt: 0
  property bool sleepFading: false
  readonly property real sleepRemainingMs: sleepEndsAt > 0 ? Math.max(0, sleepEndsAt - nowMs) : 0

  // ---------------------------------------------------------------- visualiser and motion

  property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var visualizerDemand: ({})
  property int panelsOpen: 0
  property string motion: "full"
  readonly property bool reducedMotion: motion === "reduced"
  readonly property bool spectrumShouldRun: playing && !reducedMotion
    && Object.keys(visualizerDemand).length > 0

  // Kept for Omarchy's audio panel, which highlights the stream of the
  // resolved media service's activePlayer.
  readonly property var activePlayer: {
    var list = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < list.length; i++)
      if (String(list[i].dbusName || "").indexOf("cliamp") !== -1) return list[i]
    return null
  }

  signal panelRequest(string mode)

  // ================================================================ processes

  Component {
    id: runnerComponent

    Item {
      id: job
      property var argv: []
      property var callback: null
      property int timeoutMs: 30000
      property int code: -1
      property bool exited: false
      property bool outDone: false
      property bool errDone: false
      property bool finished: false

      function finish() {
        if (finished) return
        finished = true
        var cb = callback
        callback = null
        if (cb) {
          try { cb(code, outCollector.text || "", errCollector.text || "") }
          catch (e) { console.warn("tyler.media: " + e) }
        }
        job.destroy()
      }

      function settle() {
        if (exited && outDone && errDone) finish()
      }

      Process {
        id: proc
        command: job.argv
        stdout: StdioCollector {
          id: outCollector
          onStreamFinished: { job.outDone = true; job.settle() }
        }
        stderr: StdioCollector {
          id: errCollector
          onStreamFinished: { job.errDone = true; job.settle() }
        }
        onExited: function(exitCode) {
          job.code = exitCode
          job.exited = true
          grace.start()
          job.settle()
        }
        onRunningChanged: if (!running) grace.start()
      }

      Timer { id: grace; interval: 400; onTriggered: job.finish() }

      Timer {
        interval: job.timeoutMs
        running: true
        onTriggered: {
          if (proc.running) proc.signal(15)
          job.code = 124
          job.finish()
        }
      }

      Component.onCompleted: proc.running = true
    }
  }

  function spawn(argv, callback, timeoutMs) {
    var j = runnerComponent.createObject(root, {
      argv: argv, callback: callback || null, timeoutMs: timeoutMs || 30000
    })
    if (!j && callback) callback(-1, "", "could not run " + argv[0])
  }

  function call(op, params, done, timeoutMs) {
    spawn(["cliamp", "remote", "call", op, "--params", JSON.stringify(params || {}), "--wait"],
      function(code, out, err) {
        var result = MediaModel.parseJob(code, out, err)
        if (done) done(result)
      }, timeoutMs || 45000)
  }

  function lastLine(text) {
    return String(text || "").trim().split("\n").pop().replace(/^juice-media: /, "").slice(0, 160)
  }

  // ================================================================ link lifecycle

  Process {
    id: events
    command: ["cliamp", "remote", "events", "runtime.state"]
    running: false
    stdout: SplitParser { onRead: function(line) { root.consumeEvent(line) } }
    onExited: root.eventsEnded()
  }

  Timer {
    id: reconnect
    interval: 4000
    onTriggered: if (!events.running) events.running = true
  }

  function consumeEvent(line) {
    var data
    try { data = JSON.parse(line) } catch (e) { return }
    if (!data) return
    if (data.event === "system.overflow") {
      events.running = false
      return
    }
    if (data.event !== "runtime.state" || !data.data) return
    // Retained and event positions are as of `time`; a fresh state read follows.
    applySnapshot(data.data, Number(data.time || 0) * 1000 || Date.now(), false)
    requestState()
  }

  function eventsEnded() {
    var wasConnected = connected
    if (wasConnected) saveSession()
    // The player itself, not `cliamp remote …` clients like this service's own.
    spawn(["pgrep", "-f", "^([^ ]*/)?cliamp( -.*)?$"], function(code) {
      if (events.running) return
      var alive = code === 0
      if (alive || (startDeadline > 0 && Date.now() < startDeadline)) {
        // A dropped stream from a live cliamp (overflow, restart) reconnects
        // quietly; only a cliamp that is still coming up reads as "starting".
        if (!wasConnected) root.link = "starting"
        reconnect.interval = 800
      } else {
        root.becomeAbsent()
        reconnect.interval = 4000
      }
      reconnect.restart()
    }, 5000)
  }

  function becomeAbsent() {
    if (pending) failPending("cliamp quit")
    if (link === "absent") return
    link = "absent"
    snap = MediaModel.emptySnapshot()
    buffering = false
    freshMark = null
    ramp = null
    queueItems = []
    playNextItems = []
    bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    if (sleepEndsAt > 0) cancelSleep()
    whenPlaying = []
  }

  function handleConnected() {
    link = "connected"
    startDeadline = 0
    applyFadeRestore()
    var queued = whenConnected
    whenConnected = []
    for (var i = 0; i < queued.length; i++) queued[i]()
    if (panelsOpen > 0) refreshQueue()
  }

  property bool stateBusy: false
  property bool stateAgain: false

  function requestState() {
    if (link === "absent") return
    if (stateBusy) { stateAgain = true; return }
    stateBusy = true
    spawn(["cliamp", "remote", "state"], function(code, out) {
      root.stateBusy = false
      if (code === 0) {
        try {
          var data = JSON.parse(out)
          if (data && data.snapshot) root.applySnapshot(data.snapshot, Date.now(), true)
        } catch (e) {}
      }
      if (root.stateAgain) {
        root.stateAgain = false
        root.requestState()
      }
    }, 8000)
  }

  function applySnapshot(raw, positionAt, fresh) {
    var next = MediaModel.normalizeSnapshot(raw)
    var oldPath = trackPath
    var oldState = snap.state
    snap = next
    posBase = next.position
    posAt = positionAt
    nowMs = Date.now()
    if (!fading && !volumeInFlight && isNaN(wantedVolume) && Date.now() > volumeHoldUntil)
      volume = next.volume
    if (link !== "connected") handleConnected()
    if (trackPath !== oldPath) handleTrackMove()
    if (oldState !== next.state && oldState === "playing") saveSession()
    if (next.eqPreset === "Custom" && next.eqBands.length === 10) rememberCustomEq(next.eqBands)
    if (!fresh) return
    if (next.streamError) setError(next.streamError)
    evaluatePending()
    if (playing && !pending && !buffering && whenPlaying.length) {
      var queued = whenPlaying
      whenPlaying = []
      for (var i = 0; i < queued.length; i++) queued[i]()
    }
  }

  function handleTrackMove() {
    var path = trackPath
    metaPath = path
    chapters = []
    artPath = ""
    if (path) saveSession()
    if (!MediaModel.youtubeId(path)) return
    spawn([binDir + "/juice-media-chapters", path], function(code, out) {
      if (root.metaPath !== path) return
      try {
        var data = JSON.parse(out)
        root.chapters = MediaModel.normalizeChapters(data.chapters)
        root.artPath = String(data.art || "")
      } catch (e) {}
    }, 150000)
  }

  // ================================================================ confirmation

  property int pendingSerial: 0

  function beginPending(action, kind, options) {
    var o = options || {}
    pendingSerial += 1
    pending = {
      id: pendingSerial,
      action: action,
      kind: kind,
      jobDone: o.jobDone === true,
      deadline: Date.now() + (o.timeoutMs || (kind === "paused" ? 6000 : 30000)),
      fromPath: trackPath,
      fromIndex: snap.index,
      fromPos: position,
      requireChange: o.requireChange === true,
      target: o.target === undefined ? 0 : o.target,
      lastPos: -1,
      lastPath: "",
      osd: o.osd || "",
      onConfirm: o.onConfirm || null
    }
    pollTimer.restart()
    requestState()
  }

  function markJobDone() {
    if (!pending) return
    var p = Object.assign({}, pending)
    p.jobDone = true
    p.lastPos = -1
    pending = p
    requestState()
  }

  // A job's result only settles the press that submitted it; a newer press
  // has already replaced that one.
  function submit(op, params, done) {
    var id = pending ? pending.id : 0
    call(op, params, function(r) {
      var current = root.pending && root.pending.id === id
      if (current && r.ok) root.markJobDone()
      else if (current) root.failPending(r.error)
      else if (!r.ok) root.setError(r.error)
      if (done) done(r)
    })
  }

  function evaluatePending() {
    var p = pending
    if (!p) {
      evaluateStall()
      return
    }
    if (snap.streamError && p.kind !== "paused") {
      failPending(snap.streamError)
      return
    }
    if (!p.jobDone) return
    if (p.kind === "paused") {
      if (snap.state !== "playing") confirmPending()
      return
    }
    if (p.kind === "seek" && snap.state === "paused" && Math.abs(snap.position - p.target) < 6) {
      confirmPending()
      return
    }
    if (snap.state !== "playing") return
    if (p.requireChange && trackPath === p.fromPath && snap.index === p.fromIndex
        && !(snap.position + 5 < p.fromPos)) return
    if (p.kind === "seek" && Math.abs(snap.position - p.target) > 8) return
    if (p.lastPos >= 0 && p.lastPath === trackPath && snap.position > p.lastPos + 0.15) {
      confirmPending()
      return
    }
    var next = Object.assign({}, p)
    next.lastPos = snap.position
    next.lastPath = trackPath
    pending = next
  }

  function evaluateStall() {
    if (snap.state !== "playing") {
      buffering = false
      freshMark = null
      return
    }
    var now = Date.now()
    var mark = freshMark
    if (!mark || mark.path !== trackPath) {
      if (mark) buffering = true    // cliamp moved on by itself; wait for audio
      freshMark = { path: trackPath, pos: snap.position, at: now }
      return
    }
    if (snap.position > mark.pos + 0.3) {
      buffering = false
      freshMark = { path: trackPath, pos: snap.position, at: now }
      if (errorText && !snap.streamError) clearError()
    } else if (now - mark.at > 2500) {
      buffering = true
    }
  }

  function confirmPending() {
    var p = pending
    pending = null
    buffering = false
    freshMark = { path: trackPath, pos: snap.position, at: Date.now() }
    clearError()
    if (p.kind === "paused") finishFade()
    if (p.onConfirm) p.onConfirm()
    if (p.osd) showOsd(p.osd, osdText())
  }

  function failPending(message) {
    var p = pending
    pending = null
    buffering = false
    setError(message || "cliamp didn't respond")
    if (p) {
      ramp = null
      finishFade()
    }
  }

  Timer {
    id: pollTimer
    interval: 350
    repeat: true
    running: root.pending !== null || root.buffering
    onTriggered: {
      var p = root.pending
      if (p && Date.now() > p.deadline) {
        root.failPending(p.kind === "paused" ? "cliamp didn't pause" : "No audio from cliamp yet")
        return
      }
      root.requestState()
    }
  }

  // Resync position and catch stalls while playing quietly.
  Timer {
    interval: 8000
    repeat: true
    running: root.playing && root.pending === null && !root.buffering
    onTriggered: root.requestState()
  }

  // ================================================================ errors

  function setError(message) {
    errorText = String(message || "").slice(0, 160)
    errorTimer.restart()
  }

  function clearError() {
    errorText = ""
    errorTimer.stop()
  }

  Timer {
    id: errorTimer
    interval: 12000
    onTriggered: root.errorText = ""
  }

  // ================================================================ volume

  function flushVolume() {
    if (isNaN(wantedVolume) || volumeInFlight) return
    var value = wantedVolume
    wantedVolume = NaN
    volumeInFlight = true
    lastSentVolume = value
    call("volume", { value: value }, function(r) {
      root.volumeInFlight = false
      if (!r.ok && !root.fading) root.setError("Volume: " + r.error)
      root.flushVolume()
    }, 8000)
  }

  function sendVolume(value) {
    if (!connected) return
    wantedVolume = MediaModel.clampVolume(value)
    flushVolume()
  }

  function currentLevel() {
    return isNaN(lastSentVolume) ? snap.volume : lastSentVolume
  }

  function setVolume(db) {
    var v = MediaModel.clampVolume(Math.round(Number(db) * 2) / 2)
    if (!connected || isNaN(v)) return
    if (sleepFading) cancelSleep()
    volumeHoldUntil = Date.now() + 1500
    volume = v
    if (fading) {
      fadeBase = v
      persistFade(v)
      if (ramp && ramp.resume) ramp.to = v
      return
    }
    sendVolume(v)
  }

  function adjustVolume(delta) {
    setVolume(volume + delta)
  }

  function startRamp(from, to, ms, resume, done) {
    ramp = { from: from, to: to, start: Date.now(), ms: ms, resume: resume, done: done || null }
  }

  function stepRamp() {
    var r = ramp
    if (!r) return
    var t = Math.min(1, (Date.now() - r.start) / r.ms)
    sendVolume(Math.round((r.from + (r.to - r.from) * MediaModel.easeInOut(t)) * 10) / 10)
    if (t >= 1) {
      ramp = null
      if (r.done) r.done()
    }
  }

  Timer {
    interval: 45
    repeat: true
    running: root.ramp !== null
    onTriggered: root.stepRamp()
  }

  function beginFade() {
    if (isNaN(fadeBase)) fadeBase = volume
    persistFade(fadeBase)
  }

  // Put the resting volume back exactly, whatever the fade left behind.
  function finishFade() {
    if (isNaN(fadeBase)) return
    var base = fadeBase
    fadeBase = NaN
    ramp = null
    volume = base
    sendVolume(base)
    persistFade(NaN)
  }

  function applyFadeRestore() {
    if (!savedLoaded || !connected || fading) return
    var v = Number(saved.fadeRestore)
    if (saved.fadeRestore === null || saved.fadeRestore === undefined || isNaN(v)) return
    volume = v
    sendVolume(v)
    persistFade(NaN)
  }

  // ================================================================ transport

  // A manual pause or play during the sleep timer's last minute takes over.
  function dropSleepFade() {
    if (!sleepFading) return
    sleepFading = false
    sleepEndsAt = 0
  }

  function pauseWithFade() {
    if (!connected) return false
    clearError()
    dropSleepFade()
    beginFade()
    beginPending("pause", "paused")
    startRamp(currentLevel(), MediaModel.minVolume, 600, false, function() {
      root.submit("pause", {})
    })
    return true
  }

  function resumeWithFade() {
    if (!connected) return false
    clearError()
    dropSleepFade()
    beginFade()
    ramp = null
    beginPending("play", "audio", {
      onConfirm: function() {
        var to = isNaN(root.fadeBase) ? root.volume : root.fadeBase
        root.startRamp(MediaModel.minVolume, to, 1200, true, function() { root.finishFade() })
      }
    })
    // Quiet first, then play, so the resume never starts at full volume.
    var mine = pending.id
    wantedVolume = NaN
    lastSentVolume = MediaModel.minVolume
    call("volume", { value: MediaModel.minVolume }, function() {
      if (root.pending && root.pending.id === mine) root.submit("play", {})
    }, 8000)
    return true
  }

  function togglePlay(osd) {
    if (link === "absent") {
      startFocusStation()
      return true
    }
    if (!connected) return false
    var heading = targetState
    if (heading === "playing") {
      pauseWithFade()
      if (osd) showOsd("media-pause", "Paused")
    } else {
      resumeWithFade()
      if (osd) showOsd("media-play", osdText())
    }
    return true
  }

  function play() { return connected && targetState !== "playing" ? resumeWithFade() : false }
  function pause() { return connected && targetState === "playing" ? pauseWithFade() : false }

  function stepItem(direction, osd) {
    if (!connected) return false
    clearError()
    var op = direction > 0 ? "next" : "prev"
    beginPending(op, "audio", {
      requireChange: true,
      osd: osd ? (direction > 0 ? "media-next" : "media-previous") : ""
    })
    submit(op, {})
    return true
  }

  function navigate(direction, osd) {
    if (!connected) return false
    var nav = MediaModel.navigation(chapters, position, direction)
    if (nav.kind === "seek" && snap.seekable)
      return seekTo(nav.to, direction > 0 ? "next" : "previous",
        osd ? (direction > 0 ? "media-next" : "media-previous") : "")
    return stepItem(direction, osd)
  }

  function next(osd) { return navigate(1, osd) }
  function previous(osd) { return navigate(-1, osd) }
  function nextItem() { return stepItem(1, false) }
  function previousItem() { return stepItem(-1, false) }

  function seekTo(seconds, action, osd) {
    if (!connected || !snap.seekable) return false
    clearError()
    var target = Math.max(0, Number(seconds) || 0)
    if (snap.duration > 0) target = Math.min(target, snap.duration - 1)
    posBase = target
    posAt = Date.now()
    beginPending(action || "seek", "seek", { target: target, osd: osd || "" })
    submit("seek.absolute", { value: target })
    return true
  }

  // ================================================================ stations

  function launchCliamp(playlist, then) {
    clearError()
    link = "starting"
    startDeadline = Date.now() + 30000
    if (then) whenConnected = whenConnected.concat([then])
    if (playlist) {
      loadedPlaylist = playlist
      whenConnected = whenConnected.concat([function() {
        if (!root.pending) root.beginPending("start", "audio", { jobDone: true, timeoutMs: 40000 })
      }])
    }
    var argv = [launcher, "launch"]
    if (playlist) argv = argv.concat(["--playlist", playlist])
    spawn(argv, function(code, out, err) {
      if (code !== 0) {
        root.startDeadline = 0
        root.whenConnected = []
        if (root.link === "starting") root.link = "absent"
        root.setError(root.lastLine(err) || "cliamp didn't start")
      }
      if (!events.running) events.running = true
    }, 60000)
    reconnect.interval = 800
    reconnect.restart()
  }

  function playPlaylist(name) {
    if (!name) return false
    loadedPlaylist = name
    if (link === "absent") {
      launchCliamp(name)
      return true
    }
    if (!connected) return false
    clearError()
    finishFade()
    beginPending("load", "audio", { requireChange: false, timeoutMs: 40000 })
    submit("load", { playlist: name })
    return true
  }

  function trackPayload(t) {
    return { path: t.path, title: t.title || "", artist: t.artist || "",
             stream: t.stream === true, realtime: t.realtime === true }
  }

  function playTrack(t, then) {
    if (!t || !t.path) return false
    if (link === "absent") {
      launchCliamp("", function() { root.playTrack(t, then) })
      return true
    }
    if (!connected) return false
    clearError()
    finishFade()
    beginPending("play", "audio", { requireChange: t.path !== trackPath, timeoutMs: 40000 })
    if (then) whenPlaying = whenPlaying.concat([then])
    submit("track.play", { track: trackPayload(t) })
    return true
  }

  function playNextTrack(t) {
    if (!connected || !t || !t.path) return
    call("track.queue", { track: trackPayload(t) }, function(r) {
      if (!r.ok) root.setError(r.error)
      root.refreshQueue()
    })
  }

  function queuePlay(index) {
    if (!connected) return
    clearError()
    finishFade()
    beginPending("play", "audio", { requireChange: index !== snap.index, timeoutMs: 40000 })
    submit("queue.play", { index: index, if_revision: snap.playlistRevision }, function() { root.refreshQueue() })
  }

  function queueEnqueue(index) {
    if (!connected) return
    call("queue.enqueue", { index: index, if_revision: snap.playlistRevision }, function(r) {
      if (!r.ok) root.setError(r.error)
      root.refreshQueue()
    })
  }

  function removePlayNext(index) {
    if (!connected) return
    call("playnext.remove", { index: index }, function(r) {
      if (!r.ok) root.setError(r.error)
      root.refreshQueue()
    })
  }

  function refreshQueue() {
    if (!connected) return
    call("queue.list", { offset: 0, limit: 200 }, function(r) {
      if (!r.ok) return
      var list = Array.isArray(r.result.tracks) ? r.result.tracks : []
      var out = []
      for (var i = 0; i < list.length; i++) {
        var t = MediaModel.normalizeTrack(list[i])
        if (t) { t.index = i; out.push(t) }
      }
      root.queueItems = out
    })
    call("playnext.list", { offset: 0, limit: 50 }, function(r) {
      if (!r.ok) return
      var list = Array.isArray(r.result.tracks) ? r.result.tracks : []
      var out = []
      for (var i = 0; i < list.length; i++) {
        var t = MediaModel.normalizeTrack(list[i])
        if (t) { t.index = i; out.push(t) }
      }
      root.playNextItems = out
    })
  }

  function refreshPlaylists() {
    spawn(["find", cliampDir + "/playlists", "-maxdepth", "1", "-name", "*.toml", "-printf", "%f\\n"],
      function(code, out) {
        var names = String(out || "").split("\n").filter(function(n) { return n.length > 5 })
          .map(function(n) { return n.slice(0, -5) })
        names.sort(function(a, b) { return a.localeCompare(b) })
        root.playlists = names
      }, 5000)
  }

  function panelOpened() {
    panelsOpen += 1
    nowMs = Date.now()
    refreshPlaylists()
    refreshQueue()
    if (connected) requestState()
  }

  function panelClosed() {
    panelsOpen = Math.max(0, panelsOpen - 1)
  }

  function setVisualizerDemand(key, on) {
    var next = Object.assign({}, visualizerDemand)
    if (on) next[key] = true
    else delete next[key]
    visualizerDemand = next
  }

  // ================================================================ session, focus station

  function writeSaved(next) {
    saved = next
    stateFile.setText(JSON.stringify(next))
  }

  function patchSaved(key, value) {
    var next = Object.assign({}, saved)
    next[key] = value
    writeSaved(next)
  }

  function persistFade(value) {
    patchSaved("fadeRestore", isNaN(value) ? null : value)
  }

  function loadSaved(text) {
    try {
      var data = JSON.parse(text || "{}")
      saved = {
        lastSession: data.lastSession || null,
        focusStation: data.focusStation || null,
        customBands: Array.isArray(data.customBands) ? data.customBands : null,
        fadeRestore: data.fadeRestore === undefined ? null : data.fadeRestore
      }
    } catch (e) {}
    savedLoaded = true
    applyFadeRestore()
  }

  function saveSession() {
    if (!savedLoaded || !connected || !track || !trackPath) return
    var live = !track.realtime && snap.duration > 0
    var previous = saved.lastSession || {}
    var session = {
      path: trackPath,
      title: track.title,
      artist: track.artist,
      stream: track.stream,
      realtime: track.realtime,
      playlist: loadedPlaylist || configPlaylist,
      position: live ? Math.floor(position) : 0,
      savedAt: Date.now()
    }
    if (previous.path === session.path && previous.playlist === session.playlist
        && Math.abs((previous.position || 0) - session.position) < 5) return
    patchSaved("lastSession", session)
  }

  function rememberCustomEq(bands) {
    var current = saved.customBands
    if (current && current.length === bands.length
        && current.every(function(v, i) { return Math.abs(v - bands[i]) < 0.01 })) return
    patchSaved("customBands", bands.slice())
  }

  function resumeLast() {
    var session = saved.lastSession
    if (!session || !session.path) return startDefault()
    var seekTarget = !session.realtime && session.position > 20 ? session.position : 0
    function seekBack() {
      if (seekTarget > 0 && root.trackPath === session.path && Math.abs(root.position - seekTarget) > 10)
        root.seekTo(seekTarget, "resume")
    }
    if (link === "absent") {
      if (session.playlist) {
        launchCliamp(session.playlist, function() {
          root.whenPlaying = root.whenPlaying.concat([function() {
            if (root.trackPath === session.path) seekBack()
            else root.playTrack(session, seekBack)
          }])
        })
      } else {
        playTrack(session, seekBack)
      }
      return true
    }
    if (!connected) return false
    if (trackPath === session.path) {
      if (targetState !== "playing") {
        resumeWithFade()
        whenPlaying = whenPlaying.concat([seekBack])
      } else seekBack()
      return true
    }
    return playTrack(session, seekBack)
  }

  // Drop cliamp's own window down (starting it first when needed).
  function showPlayer() {
    Quickshell.execDetached(link === "absent" ? [launcher, "launch", "--show"] : [launcher, "show"])
  }

  function startDefault() {
    var name = loadedPlaylist || configPlaylist || (playlists.length ? playlists[0] : "")
    if (name) return playPlaylist(name)
    if (link === "absent") launchCliamp("")
    else if (connected) resumeWithFade()
    return true
  }

  function isFocusStation(station) {
    return MediaModel.stationKey(saved.focusStation) === MediaModel.stationKey(station)
  }

  function toggleFocusStation(station) {
    patchSaved("focusStation", isFocusStation(station) ? null : station)
  }

  function startFocusStation() {
    if (playing && targetState === "playing") return "already-playing"
    if (link === "starting") return "starting"
    var station = saved.focusStation
    if (station && station.kind === "playlist") return playPlaylist(station.name) ? "starting" : "unhandled"
    if (station && station.kind === "track") return playTrack(station) ? "starting" : "unhandled"
    if (connected && snap.state === "paused") return resumeWithFade() ? "resumed" : "unhandled"
    return resumeLast() ? "starting" : "unhandled"
  }

  // ================================================================ EQ, lyrics, sleep

  function setEqPreset(name) {
    if (!connected) return
    call("eq", { name: name }, function(r) { if (!r.ok) root.setError("EQ: " + r.error) })
  }

  function restoreCustomEq() {
    var bands = saved.customBands
    if (!connected || !bands || bands.length !== 10) return
    function step(i) {
      if (i >= bands.length) return
      root.call("eq", { band: i, value: Number(bands[i]) || 0 }, function(r) {
        if (!r.ok) root.setError("EQ: " + r.error)
        else step(i + 1)
      })
    }
    step(0)
  }

  function fetchLyrics(force) {
    var key = lyricsKey
    if (!key) return
    if (!force && lyrics.key === key && lyrics.state !== "idle") return
    if (!force && lyricsCache[key]) {
      lyrics = lyricsCache[key]
      return
    }
    var offset = chapter ? chapter.start : 0
    lyrics = { key: key, state: "loading", synced: false, offset: offset, lines: [] }
    function done(lines, synced) {
      var entry = {
        key: key, state: lines.length ? "ok" : "none", synced: synced, offset: offset,
        lines: lines.slice(0, 400).map(function(l) {
          return { start: Number(l.start) || 0, text: String(l.text || "") }
        })
      }
      var cache = Object.assign({}, root.lyricsCache)
      cache[key] = entry
      root.lyricsCache = cache
      if (root.lyricsKey === key) root.lyrics = entry
    }
    var parts = chapter ? MediaModel.splitArtistTitle(chapter.title) : null
    if (parts) {
      spawn([launcher, "lyrics", parts.artist, parts.title], function(code, out) {
        try {
          var data = JSON.parse(out)
          done(Array.isArray(data.lines) ? data.lines : [], data.synced === true)
        } catch (e) { done([], false) }
      }, 30000)
    } else if (connected) {
      call("lyrics", {}, function(r) {
        var lines = r.ok && Array.isArray(r.result.lyrics) ? r.result.lyrics : []
        done(lines, lines.some(function(l) { return Number(l.start) > 0 }))
      }, 30000)
    } else {
      done([], false)
    }
  }

  onLyricsKeyChanged: if (lyricsWanted) fetchLyrics(false)
  onLyricsWantedChanged: if (lyricsWanted) fetchLyrics(false)

  function setSleep(minutes) {
    cancelSleep()
    var m = Math.max(0, Math.round(Number(minutes) || 0))
    if (m > 0) sleepEndsAt = Date.now() + m * 60000
    nowMs = Date.now()
  }

  function cancelSleep() {
    var wasFading = sleepFading
    sleepFading = false
    sleepEndsAt = 0
    if (wasFading && !pending) finishFade()
  }

  // The last minute fades out; then pause and put the volume back.
  function sleepTick() {
    var left = sleepEndsAt - Date.now()
    if (!playing) {
      if (left <= 0) cancelSleep()
      return
    }
    if (left <= 60000 && !sleepFading) {
      sleepFading = true
      beginFade()
    }
    if (!sleepFading) return
    if (isNaN(fadeBase)) beginFade()
    if (left <= 0) {
      sleepFading = false
      sleepEndsAt = 0
      beginPending("sleep", "paused")
      submit("pause", {})
      return
    }
    var t = 1 - left / 60000
    sendVolume(Math.round((fadeBase + (MediaModel.minVolume - fadeBase) * t) * 10) / 10)
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.sleepEndsAt > 0
    onTriggered: root.sleepTick()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.playing || root.sleepEndsAt > 0 || root.panelsOpen > 0
    onTriggered: {
      root.nowMs = Date.now()
      if (!root.playing) return
      root.sessionTicks += 1
      if (root.sessionTicks % 15 === 0) root.saveSession()
    }
  }

  // ================================================================ spectrum

  onSpectrumShouldRunChanged: {
    if (spectrumShouldRun) spectrum.running = true
    else spectrum.running = false
  }

  Process {
    id: spectrum
    command: [root.binDir + "/juice-media-spectrum"]
    running: false
    stdout: SplitParser { onRead: function(line) { root.consumeBands(line) } }
    onExited: if (root.spectrumShouldRun) spectrumRetry.restart()
  }

  Timer {
    id: spectrumRetry
    interval: 5000
    onTriggered: if (root.spectrumShouldRun && !spectrum.running) spectrum.running = true
  }

  function consumeBands(line) {
    try {
      var data = JSON.parse(line)
      if (data && Array.isArray(data.bands) && data.bands.length === 10) bands = data.bands
    } catch (e) {}
  }

  // ================================================================ OSD and status

  function osdText() {
    return title + (subtitle ? " - " + subtitle : "")
  }

  function showOsd(icon, message) {
    if (!shell || typeof shell.summon !== "function") return
    shell.summon("omarchy.osd", JSON.stringify({ icon: icon || "media", message: message || "Music" }))
  }

  function statusObject() {
    return {
      status: status,
      link: link,
      state: snap.state,
      title: title,
      subtitle: subtitle,
      chapter: chapter ? { index: chapterIndex, count: chapters.length, title: chapter.title } : null,
      position: Math.round(position),
      duration: Math.round(snap.duration),
      volume: volume,
      playlist: loadedPlaylist || configPlaylist,
      sleepRemaining: Math.round(sleepRemainingMs / 1000),
      error: errorText
    }
  }

  // ================================================================ files

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    preload: false
    onLoaded: root.loadSaved(text())
    onLoadFailed: root.loadSaved("{}")
  }

  FileView {
    id: launchFile
    path: root.stateDir + "/launch.json"
    watchChanges: true
    printErrors: false
    preload: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text() || "{}")
        if (data.playlist) root.loadedPlaylist = String(data.playlist)
      } catch (e) {}
    }
  }

  FileView {
    path: root.cliampDir + "/config.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.configPlaylist = String(MediaModel.parseToml(text()).top.playlist || "")
  }

  FileView {
    path: root.cliampDir + "/radios.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.radios = MediaModel.tomlTracks(MediaModel.parseToml(text()).tables.station)
      .map(function(t) { t.stream = true; return t })
    onLoadFailed: root.radios = []
  }

  FileView {
    path: root.cliampDir + "/favorites.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.favourites = MediaModel.tomlTracks(MediaModel.parseToml(text()).tables.entry)
    onLoadFailed: root.favourites = []
  }

  FileView {
    path: root.cliampDir + "/history.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var entries = (MediaModel.parseToml(text()).tables.entry || []).slice()
      entries.sort(function(a, b) { return String(b.played_at || "").localeCompare(String(a.played_at || "")) })
      root.history = MediaModel.dedupeByPath(MediaModel.tomlTracks(entries), 10)
    }
    onLoadFailed: root.history = []
  }

  // Reduced motion comes from the tyler.juice state bus; keep the last good value.
  FileView {
    id: busFile
    path: root.busPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text() || "{}")
        if (data.motion === "reduced" || data.motion === "full") root.motion = data.motion
      } catch (e) {}
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: busFile.reload()
  }

  Timer {
    id: startupTimer
    interval: 150
    onTriggered: {
      stateFile.reload()
      launchFile.reload()
      root.refreshPlaylists()
      events.running = true
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.link === "starting" && root.startDeadline > 0
    onTriggered: {
      if (Date.now() < root.startDeadline) return
      root.startDeadline = 0
      root.whenConnected = []
      if (root.link === "starting") root.link = "absent"
      root.setError("cliamp didn't start")
    }
  }

  Component.onCompleted: {
    ServiceBridge.publish(root)
    Quickshell.execDetached(["mkdir", "-p", stateDir])
    startupTimer.start()
  }

  Component.onDestruction: {
    ServiceBridge.clear(root)
    if (connected) saveSession()
  }

  // ================================================================ IPC

  // Media keys (`omarchy-shell media …`) once omarchy.media is disabled.
  IpcHandler {
    target: "media"

    function status(): string { return JSON.stringify(root.statusObject()) }
    function playPause(): string { return root.togglePlay(true) ? "ok" : "unhandled" }
    function play(): string { return root.play() ? "ok" : "unhandled" }
    function pause(): string { return root.pause() ? "ok" : "unhandled" }
    function next(): string { return root.next(true) ? "ok" : "unhandled" }
    function previous(): string { return root.previous(true) ? "ok" : "unhandled" }
    function sourceNext(): string { return "unhandled" }
    function sourcePrevious(): string { return "unhandled" }
    function sourceSwitch(): string { return "unhandled" }
    function sourceSwitchPrevious(): string { return "unhandled" }
    function ping(): string { return "ok" }
  }

  IpcHandler {
    target: "tyler.media"

    function status(): string { return JSON.stringify(root.statusObject()) }
    function playPause(): string { return root.togglePlay(true) ? "ok" : "unhandled" }
    function play(): string { return root.play() ? "ok" : "unhandled" }
    function pause(): string { return root.pause() ? "ok" : "unhandled" }
    function next(): string { return root.next(true) ? "ok" : "unhandled" }
    function previous(): string { return root.previous(true) ? "ok" : "unhandled" }
    function nextItem(): string { return root.nextItem() ? "ok" : "unhandled" }
    function previousItem(): string { return root.previousItem() ? "ok" : "unhandled" }
    function volumeUp(): string { root.adjustVolume(1); return MediaModel.formatDb(root.volume) }
    function volumeDown(): string { root.adjustVolume(-1); return MediaModel.formatDb(root.volume) }
    function setVolume(db: string): string { root.setVolume(Number(db)); return MediaModel.formatDb(root.volume) }
    function startFocusStation(): string { return root.startFocusStation() }
    function resumeLast(): string { return root.resumeLast() ? "ok" : "unhandled" }
    function sleep(minutes: string): string {
      root.setSleep(Number(minutes))
      return root.sleepEndsAt > 0 ? "sleeping in " + MediaModel.formatRemaining(root.sleepRemainingMs) : "off"
    }
    function openPanel(): string { root.panelRequest("open"); return "ok" }
    function closePanel(): string { root.panelRequest("close"); return "ok" }
    function togglePanel(): string { root.panelRequest("toggle"); return "ok" }
    function ping(): string { return "ok" }
  }
}
