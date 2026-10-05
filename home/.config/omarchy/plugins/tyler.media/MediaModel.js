.pragma library

// Pure helpers for tyler.media: cliamp v2 snapshot normalisation, chapter
// navigation, the TOML subset cliamp writes, and display formatting.

var minVolume = -30
var maxVolume = 6

function emptySnapshot() {
  return normalizeSnapshot({})
}

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function normalizeTrack(raw) {
  if (!raw || typeof raw !== "object" || !raw.path) return null
  return {
    title: String(raw.title || ""),
    artist: String(raw.artist || ""),
    album: String(raw.album || ""),
    path: String(raw.path),
    stream: raw.stream === true,
    realtime: raw.realtime === true,
    station: String(raw.station || ""),
    streamTitle: String(raw.stream_title || ""),
    durationSecs: num(raw.duration_secs, 0),
    index: num(raw.index, 0),
    artUrl: String(raw.album_art_url || "")
  }
}

// cliamp omits zero values (`omitempty`): a missing volume is 0 dB, a missing
// index is the first track, a missing position is the start.
function normalizeSnapshot(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  return {
    revision: num(s.revision, 0),
    playlistRevision: num(s.playlist_revision, 0),
    state: s.state === "playing" || s.state === "paused" ? s.state : "stopped",
    track: normalizeTrack(s.track),
    logical: normalizeTrack(s.logical_track),
    position: Math.max(0, num(s.position, 0)),
    duration: Math.max(0, num(s.duration, 0)),
    seekable: s.seekable === true,
    volume: clampVolume(num(s.volume, 0)),
    index: num(s.index, 0),
    total: num(s.total, 0),
    playNextTotal: num(s.play_next_total, 0),
    shuffle: s.shuffle === true,
    repeat: String(s.repeat || ""),
    mono: s.mono === true,
    speed: num(s.speed, 1) || 1,
    eqPreset: String(s.eq_preset || ""),
    eqBands: Array.isArray(s.eq_bands) ? s.eq_bands.map(function(v) { return num(v, 0) }) : [],
    visualizer: String(s.visualizer || ""),
    streamError: String(s.stream_error || "")
  }
}

function clampVolume(value) {
  return Math.max(minVolume, Math.min(maxVolume, num(value, 0)))
}

function youtubeId(url) {
  var m = String(url || "").match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|live\/|shorts\/|embed\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/)
  return m ? m[1] : ""
}

function basename(path) {
  var text = String(path || "").replace(/[?#].*$/, "").replace(/\/+$/, "")
  var slash = text.lastIndexOf("/")
  return decodeURIComponent(slash >= 0 ? text.slice(slash + 1) : text)
}

function trackTitle(track) {
  if (!track) return ""
  if (track.stream && track.streamTitle) return track.streamTitle
  return track.title || basename(track.path)
}

function normalizeChapters(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length; i++) {
    var c = list[i] || {}
    var start = num(c.start, NaN)
    if (!isFinite(start)) continue
    out.push({ start: start, end: num(c.end, 0), title: String(c.title || "") })
  }
  out.sort(function(a, b) { return a.start - b.start })
  for (var j = 0; j < out.length; j++) {
    if (!(out[j].end > out[j].start)) out[j].end = j + 1 < out.length ? out[j + 1].start : 0
  }
  return out.length > 1 ? out : []
}

function chapterIndexAt(chapters, position) {
  var index = -1
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].start <= position + 0.25) index = i
    else break
  }
  return index
}

// Decision 3: next/previous move between chapters when the item has them,
// otherwise between playlist items. Previous restarts the chapter first
// unless it began less than four seconds ago.
function navigation(chapters, position, direction) {
  if (!chapters || chapters.length === 0) return { kind: "item" }
  var i = chapterIndexAt(chapters, position)
  if (direction > 0) {
    if (i + 1 < chapters.length) return { kind: "seek", to: chapters[i + 1].start, chapter: i + 1 }
    return { kind: "item" }
  }
  var start = i >= 0 ? chapters[i].start : 0
  if (position - start > 4) return { kind: "seek", to: start, chapter: i }
  if (i > 0) return { kind: "seek", to: chapters[i - 1].start, chapter: i - 1 }
  return { kind: "item" }
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

function formatTime(seconds) {
  var s = Math.max(0, Math.floor(num(seconds, 0)))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  return h > 0 ? h + ":" + pad2(m) + ":" + pad2(r) : m + ":" + pad2(r)
}

function formatDb(value) {
  var v = Math.round(num(value, 0) * 10) / 10
  if (v === 0) return "0 dB"
  var text = String(Math.abs(v))
  return (v < 0 ? "\u2212" : "+") + text + " dB"
}

function formatRemaining(ms) {
  var s = Math.max(0, Math.ceil(ms / 1000))
  var m = Math.floor(s / 60)
  return m >= 1 ? m + " min" : s + " s"
}

// "Artist - Title" in a mix chapter, minus a leading track number.
function splitArtistTitle(text) {
  var clean = String(text || "").replace(/^\s*\d{1,3}[.)\-:]?\s+/, "").replace(/\s*[\[(][^\])]*[\])]\s*$/, "").trim()
  var m = clean.match(/^(.+?)\s+[-\u2013\u2014]\s+(.+)$/)
  return m ? { artist: m[1].trim(), title: m[2].trim() } : null
}

// ---- TOML subset: [[table]] arrays of key = value lines (cliamp's files) ----

function tomlString(text) {
  var out = ""
  for (var i = 1; i < text.length; i++) {
    var ch = text[i]
    if (ch === "\"") return out
    if (ch === "\\" && i + 1 < text.length) {
      var next = text[++i]
      if (next === "n") out += "\n"
      else if (next === "t") out += "\t"
      else if (next === "u" && i + 4 < text.length) {
        out += String.fromCharCode(parseInt(text.substr(i + 1, 4), 16))
        i += 4
      } else out += next
    } else out += ch
  }
  return out
}

function tomlValue(text) {
  var t = text.trim()
  if (t[0] === "\"") return tomlString(t)
  if (t[0] === "'") return t.slice(1, t.indexOf("'", 1))
  if (t === "true") return true
  if (t === "false") return false
  var n = Number(t.replace(/\s+#.*$/, ""))
  return isFinite(n) ? n : t
}

// Returns { top: {key: value}, tables: {name: [ {key: value} ]} }.
function parseToml(text) {
  var result = { top: {}, tables: {} }
  var current = result.top
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line[0] === "#") continue
    var table = line.match(/^\[\[\s*([^\]]+?)\s*\]\]$/)
    if (table) {
      if (!result.tables[table[1]]) result.tables[table[1]] = []
      current = {}
      result.tables[table[1]].push(current)
      continue
    }
    if (line[0] === "[") { current = {}; continue }
    var eq = line.indexOf("=")
    if (eq <= 0) continue
    var key = line.slice(0, eq).trim().replace(/^"|"$/g, "")
    current[key] = tomlValue(line.slice(eq + 1))
  }
  return result
}

function tomlTracks(entries) {
  var out = []
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var path = String(e.path || e.url || "")
    if (!path) continue
    out.push({
      path: path,
      title: String(e.title || e.name || basename(path)),
      artist: String(e.artist || ""),
      stream: /^https?:/.test(path),
      realtime: e.realtime === true
    })
  }
  return out
}

function dedupeByPath(list, limit) {
  var seen = {}
  var out = []
  for (var i = 0; i < list.length && out.length < limit; i++) {
    var item = list[i]
    if (!item || !item.path || seen[item.path]) continue
    seen[item.path] = true
    out.push(item)
  }
  return out
}

// The v2 job record printed by `cliamp remote call … --wait`.
function parseJob(code, stdout, stderr) {
  var message = String(stderr || stdout || "").trim().split("\n").pop()
  if (code === 0) {
    try {
      var data = JSON.parse(String(stdout || "{}"))
      var job = data.job || {}
      if (data.ok !== false && job.state === "succeeded")
        return { ok: true, result: job.result || {}, job: job }
      var error = job.error || data.error || {}
      message = error.detail || error.message || ("job " + (job.state || "failed"))
    } catch (e) {
      message = "unreadable reply from cliamp"
    }
  }
  if (/no such file|connection refused|connect:/i.test(message)) message = "cliamp isn't running"
  return { ok: false, error: message.slice(0, 160) }
}

function volumeGlyph(db) {
  if (db <= minVolume + 0.01) return String.fromCodePoint(0xF0581)
  if (db < -18) return String.fromCodePoint(0xF057F)
  if (db < -6) return String.fromCodePoint(0xF0580)
  return String.fromCodePoint(0xF057E)
}

function easeInOut(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
}

function stationKey(station) {
  if (!station) return ""
  return station.kind === "playlist" ? "playlist:" + station.name : "track:" + station.path
}
