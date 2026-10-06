.pragma library

// Workspace names derived from what is running in each workspace.
//
// Shared by the tyler.workspaces bar indicator and peek, and by the
// io.zet.workspace-switcher cards (imported as
// "../tyler.workspaces/WorkspaceNames.js"). A `.pragma library` script is one
// instance per engine and file, so every importer shares the focus order and
// the desktop-entry cache kept below.
//
// Rules, in order, for one window:
//   Herdr   the window running the Herdr client (the state bus names its
//           address; failing that its title is "<herd.host>: <space>") is
//           named after the Herdr space.
//   web app a Brave/Chromium app window (class "brave-x.com__home-Default") is
//           named after its desktop entry, or else its site ("X").
//   browser the site part of the tab title ("Analytics / X" -> "X").
//   terminal the project or cwd part of the title ("tyler@ak1:~/Work/juice" ->
//           "juice").
//   shell   a window drawn inside a Quickshell shell (class "org.quickshell",
//           whichever plugin drew it) is named after the desktop entry called
//           like the first part of its title ("ibara · console" -> "ibara").
//   other   the desktop entry name, or a humanised window class.
// A workspace takes the name and icon of its most recently focused window.
//
// Workspace number N spans two monitors: Hyprland workspace N on the left one
// and N + PAIR_OFFSET on the right (~/.local/bin/zet-workspace-flow).
// `workspaceFor` describes one Hyprland workspace, `pairFor` the whole number.

var NAME_MAX = 28
var PAIR_OFFSET = 10

var TERMINAL_CLASSES = [
  "alacritty", "com.mitchellh.ghostty", "ghostty", "kitty", "foot", "footclient",
  "org.wezfurlong.wezterm", "wezterm", "xterm", "konsole", "org.gnome.console",
  "org.gnome.terminal", "gnome-terminal-server", "st", "st-256color", "urxvt", "rio", "tilix"
]

var BROWSER_CLASSES = [
  "brave-browser", "brave-origin", "brave", "firefox", "chromium", "google-chrome",
  "chrome", "vivaldi-stable", "zen", "zen-browser", "librewolf", "microsoft-edge",
  "helium", "org.qutebrowser.qutebrowser", "qutebrowser", "epiphany", "org.gnome.epiphany"
]

// The app id Quickshell gives every window it draws.
var SHELL_CLASS = "org.quickshell"

// Chromium-family --app windows: "<browser>-<host>__<path>-<profile>".
var WEBAPP_RE = /^(brave|chrome|chromium|google-chrome|msedge|microsoft-edge|vivaldi|helium)-(.+)-(Default|Profile[_ ]\d+)$/i

// A browser appends its own name to the tab title.
var BROWSER_SUFFIX_RE = /\s[-\u2014\u2013]\s(Brave( Origin| Browser)?|Mozilla Firefox|Firefox|Chromium|Google Chrome|Zen Browser|Zen|Vivaldi|Microsoft\u200b? Edge|LibreWolf|Helium|qutebrowser)$/i

var BLANK_TAB_RE = /^(new tab|new private tab|untitled|about:blank|start page|private browsing)$/i

// Nerd Font fallbacks for when no desktop icon resolves. Every codepoint is
// one Omarchy's font is known to draw (see jankeesvw.workspace-name).
var GLYPHS = {
  herdr: 0xF120,     // terminal
  terminal: 0xF120,  // terminal
  browser: 0xF0AC,   // globe
  webapp: 0xF0AC,    // globe
  app: 0xF2D0        // window
}

// ---------------------------------------------------------------- text

function clean(value, max) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f<>]/g, "")
    .replace(/\s+/g, " ")
    .trim()
  var limit = max || NAME_MAX
  return text.length > limit ? text.slice(0, limit - 1).trim() + "\u2026" : text
}

function capitalise(text) {
  var value = String(text || "")
  return value ? value.charAt(0).toUpperCase() + value.slice(1) : ""
}

function normAddress(value) {
  var text = String(value || "").trim().toLowerCase()
  return text.indexOf("0x") === 0 ? text.slice(2) : text
}

function glyphFor(kind) {
  return String.fromCodePoint(GLYPHS[kind] || GLYPHS.app)
}

function numberLabel(id) {
  return Number(id) === 10 ? "0" : String(id)
}

// "com.mitchellh.ghostty" -> "Ghostty", "io.github.lgse.Strata" -> "Strata",
// "brave-origin" -> "Brave origin".
function humaniseClass(cls) {
  var value = String(cls || "")
  if (!value) return ""
  if (/^[a-z0-9-]+(\.[A-Za-z0-9_-]+){2,}$/.test(value)) value = value.split(".").pop()
  value = value.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
  return clean(capitalise(value))
}

// "x.com" -> "X", "web.telegram.org" -> "Telegram", "bbc.co.uk" -> "Bbc".
function siteLabel(host) {
  var labels = String(host || "").toLowerCase().replace(/:\d+$/, "").split(".")
    .filter(function(part) { return part !== "" })
  if (labels.length === 0) return ""
  if (labels.length === 1) return capitalise(labels[0])
  var index = labels.length - 2
  if (labels.length >= 3 && /^(co|com|org|net|ac|gov|edu)$/.test(labels[index])) index--
  return clean(capitalise(labels[index]))
}

function looksLikePath(text) {
  var value = String(text || "")
  return value === "~" || /^~?\//.test(value) || /^\.{1,2}\//.test(value)
}

// The directory a path names; a file path ("~/w/juice/src/bar.ts") gives its
// project directory, stepping over generic source folders.
var GENERIC_DIRS = ["src", "lib", "app", "bin", "test", "tests", "docs", "components", "pkg", "cmd", "internal"]

function pathLeaf(path) {
  var value = String(path || "").replace(/\/+$/, "")
  if (value === "" || value === "~") return "~"
  var parts = value.split("/").filter(function(part) { return part !== "" })
  if (parts.length === 0) return "/"
  var at = parts.length - 1
  if (at > 0 && /^[^.].*\.[A-Za-z0-9]{1,6}$/.test(parts[at])) {
    at--
    while (at > 0 && GENERIC_DIRS.indexOf(parts[at].toLowerCase()) !== -1) at--
  }
  return parts[at]
}

function terminalName(title, appName) {
  var text = clean(title, 200).replace(/^[^\w~\/.]+\s*/, "")
  if (!text) return ""
  if (appName && text.toLowerCase() === String(appName).toLowerCase()) return ""
  if (/^(alacritty|ghostty|kitty|foot|terminal|wezterm|xterm|konsole)$/i.test(text)) return ""

  var match = /^[\w.-]+@[\w.-]+:\s*(.*)$/.exec(text)        // user@host:path
  if (match) text = match[1]
  else {
    match = /^[\w.-]+:\s+(\S.*)$/.exec(text)                  // host: path
    if (match && looksLikePath(match[1])) text = match[1]
  }
  if (looksLikePath(text)) return clean(pathLeaf(text))

  // "omp · desktop-juice", "nvim ~/Work/juice/bar.ts", "btop"
  var parts = text.split(/\s+[-\u2014\u2013\u00b7|\u2022:]\s+/).filter(function(part) { return part !== "" })
  if (parts.length > 1) {
    var last = parts[parts.length - 1]
    return clean(looksLikePath(last) ? pathLeaf(last) : last)
  }
  var words = text.split(" ")
  for (var i = 1; i < words.length; i++)
    if (looksLikePath(words[i])) return clean(pathLeaf(words[i]))
  return clean(text)
}

function siteFromTitle(title, browserName) {
  var text = clean(title, 300).replace(/^\(\d+\+?\)\s*/, "").replace(BROWSER_SUFFIX_RE, "")
  if (browserName) {
    var suffix = " - " + browserName
    if (text.length > suffix.length && text.slice(-suffix.length).toLowerCase() === suffix.toLowerCase())
      text = text.slice(0, -suffix.length)
  }
  text = text.trim()
  if (!text || BLANK_TAB_RE.test(text)) return ""
  var parts = text.split(/\s+[-\u2014\u2013|\u00b7\u2022\/]\s+/).filter(function(part) { return part !== "" })
  if (parts.length > 1 && parts[parts.length - 1].length <= 24) return clean(parts[parts.length - 1])
  return clean(parts[0])
}

// ---------------------------------------------------------------- desktop entries

// Cached as plain values: a DesktopEntry object can die on a rescan. The
// cache resets whenever the number of applications changes.
var entryCache = ({})
var entryCacheSize = -1

function applicationList(entries) {
  try {
    return entries && entries.applications ? (entries.applications.values || []) : []
  } catch (e) {
    return []
  }
}

function entryInfo(entry) {
  if (!entry) return null
  var categories = []
  try { categories = entry.categories ? Array.prototype.slice.call(entry.categories) : [] } catch (e) { categories = [] }
  return { name: clean(entry.name || ""), icon: String(entry.icon || ""), categories: categories }
}

function syncCache(entries) {
  var size = applicationList(entries).length
  if (size !== entryCacheSize) {
    entryCache = ({})
    entryCacheSize = size
  }
}

// allowHeuristic is off for web-app classes: a fuzzy match on
// "brave-x.com__home-Default" lands on the browser itself.
function entryForClass(entries, cls, allowHeuristic) {
  if (!entries || !cls) return null
  syncCache(entries)
  var key = (allowHeuristic ? "h:" : "x:") + cls
  if (entryCache.hasOwnProperty(key)) return entryCache[key]

  var found = null
  try {
    found = entries.byId(cls) || entries.byId(cls.toLowerCase()) || null
    if (!found) {
      var apps = applicationList(entries)
      var lower = cls.toLowerCase()
      for (var i = 0; i < apps.length && !found; i++)
        if (apps[i] && String(apps[i].startupClass || "").toLowerCase() === lower) found = apps[i]
    }
    if (!found && allowHeuristic) found = entries.heuristicLookup(cls) || null
  } catch (e) {
    found = null
  }
  entryCache[key] = entryInfo(found)
  return entryCache[key]
}

// The desktop entry that launches a site ("omarchy-launch-webapp https://x.com/").
function entryForHost(entries, host) {
  if (!entries || !host) return null
  syncCache(entries)
  var key = "w:" + host
  if (entryCache.hasOwnProperty(key)) return entryCache[key]

  var found = null
  var needle = "://" + host.toLowerCase()
  var apps = applicationList(entries)
  for (var i = 0; i < apps.length && !found; i++) {
    var exec = ""
    try { exec = String(apps[i].execString || "").toLowerCase() } catch (e) { exec = "" }
    var at = exec.indexOf(needle)
    if (at === -1) continue
    var next = exec.charAt(at + needle.length)
    if (next === "" || next === "/" || next === "'" || next === "\"" || next === " " || next === "?") found = apps[i]
  }
  entryCache[key] = entryInfo(found)
  return entryCache[key]
}

// Every plugin window in a Quickshell shell shares SHELL_CLASS, so its title
// tells the plugins apart: the entry named like the title's first part.
// Null for other classes, or when no entry has that name.
function entryForShellWindow(entries, cls, title) {
  if (!entries || String(cls || "").toLowerCase() !== SHELL_CLASS) return null
  var lead = clean(String(title || "").split(/\s+[-\u2014\u2013\u00b7|\u2022:]\s+/)[0], 200).toLowerCase()
  if (!lead) return null
  syncCache(entries)
  var key = "s:" + lead
  if (entryCache.hasOwnProperty(key)) return entryCache[key]

  var found = null
  var apps = applicationList(entries)
  for (var i = 0; i < apps.length && !found; i++) {
    var name = ""
    try { name = String(apps[i].name || "").toLowerCase() } catch (e) { name = "" }
    if (name === lead) found = apps[i]
  }
  entryCache[key] = entryInfo(found)
  return entryCache[key]
}

function hasCategory(info, category) {
  return !!info && info.categories.indexOf(category) !== -1
}

// ---------------------------------------------------------------- state bus

function parseBus(text, previous) {
  try {
    var value = JSON.parse(String(text || ""))
    return value && typeof value === "object" && !Array.isArray(value) ? value : previous
  } catch (e) {
    return previous
  }
}

function reducedMotion(bus) {
  return !!bus && bus.motion === "reduced"
}

function herdInfo(bus) {
  var herd = bus && bus.herd && typeof bus.herd === "object" ? bus.herd : ({})
  var counts = { working: 0, blocked: 0, done: 0 }
  var agents = Array.isArray(herd.agents) ? herd.agents : []
  if (agents.length > 0) {
    for (var i = 0; i < agents.length; i++) {
      var status = agents[i] ? String(agents[i].status || "") : ""
      if (counts.hasOwnProperty(status)) counts[status]++
    }
  } else if (herd.counts && typeof herd.counts === "object") {
    counts.working = Math.max(0, Number(herd.counts.working) || 0)
    counts.blocked = Math.max(0, Number(herd.counts.blocked) || 0)
    counts.done = Math.max(0, Number(herd.counts.done) || 0)
  }
  var spaces = []
  var list = Array.isArray(herd.spaces) ? herd.spaces : []
  for (var j = 0; j < list.length; j++)
    if (list[j] && list[j].label) spaces.push(String(list[j].label))
  return {
    available: herd.available === true,
    host: String(herd.host || ""),
    windowAddress: normAddress(herd.windowAddress),
    focusedSpace: herd.focusedSpace ? String(herd.focusedSpace) : "",
    spaces: spaces,
    counts: counts
  }
}

// ---------------------------------------------------------------- focus order

// Hyprland's focusHistoryID only refreshes when the shell re-reads the client
// list, so the order is also tracked here from activeToplevel changes. A
// window noted here is more recent than any it was never seen take focus.
var focusSeq = 0
var focusRank = ({})
var lastNoted = ""

function noteFocus(address) {
  var key = normAddress(address)
  if (!key || key === lastNoted) return
  lastNoted = key
  focusSeq++
  focusRank[key] = focusSeq
}

function recency(record) {
  if (focusRank.hasOwnProperty(record.address)) return 1e9 + focusRank[record.address]
  return record.focusHistory >= 0 ? 1e6 - record.focusHistory : 0
}

function pruneFocus(liveAddresses) {
  var next = ({})
  for (var address in focusRank)
    if (liveAddresses[address]) next[address] = focusRank[address]
  focusRank = next
}

// ---------------------------------------------------------------- windows

function windowRecord(toplevel) {
  if (!toplevel) return null
  var ipc = toplevel.lastIpcObject || ({})
  var cls = ""
  if (toplevel.wayland && toplevel.wayland.appId) cls = String(toplevel.wayland.appId)
  if (!cls) cls = String(ipc["class"] || ipc.initialClass || "")
  var workspaceId = toplevel.workspace ? Number(toplevel.workspace.id)
    : Number(ipc.workspace && ipc.workspace.id)
  return {
    address: normAddress(toplevel.address || ipc.address),
    cls: cls,
    title: String(toplevel.title || ipc.title || ""),
    workspaceId: isFinite(workspaceId) ? workspaceId : 0,
    focusHistory: ipc.focusHistoryID !== undefined && ipc.focusHistoryID !== null ? Number(ipc.focusHistoryID) : -1,
    urgent: toplevel.urgent === true
  }
}

function herdSpaceFromTitle(title, herd) {
  if (!herd.host) return null
  var prefix = herd.host + ": "
  var text = String(title || "")
  if (text.indexOf(prefix) !== 0) return null
  var space = text.slice(prefix.length).trim()
  if (!space) return null
  if (herd.spaces.length > 0 && herd.spaces.indexOf(space) === -1) return null
  return space
}

function describeWindow(record, herd, entries) {
  var cls = record.cls
  var lower = cls.toLowerCase()

  var herdSpace = herdSpaceFromTitle(record.title, herd)
  var isHerd = herdSpace !== null || (!!herd.windowAddress && herd.windowAddress === record.address)
  if (isHerd) {
    var terminal = entryForClass(entries, cls, true)
    return {
      kind: "herdr",
      name: clean(herdSpace || herd.focusedSpace || "Herdr"),
      icon: terminal ? terminal.icon : "",
      glyph: glyphFor("herdr")
    }
  }

  var web = WEBAPP_RE.exec(cls)
  if (web || lower.indexOf("crx_") === 0) {
    var host = web ? web[2].split("__")[0] : ""
    var app = entryForClass(entries, cls, false) || entryForHost(entries, host)
    return {
      kind: "webapp",
      name: app && app.name ? app.name : (siteLabel(host) || siteFromTitle(record.title, "") || "Web app"),
      icon: app ? app.icon : "",
      glyph: glyphFor("webapp")
    }
  }

  var entry = entryForShellWindow(entries, cls, record.title) || entryForClass(entries, cls, true)
  var appName = entry && entry.name ? entry.name : humaniseClass(cls)

  if (TERMINAL_CLASSES.indexOf(lower) !== -1 || hasCategory(entry, "TerminalEmulator")) {
    return {
      kind: "terminal",
      name: terminalName(record.title, appName) || appName || "Terminal",
      icon: entry ? entry.icon : "",
      glyph: glyphFor("terminal")
    }
  }

  if (BROWSER_CLASSES.indexOf(lower) !== -1 || hasCategory(entry, "WebBrowser")) {
    return {
      kind: "browser",
      name: siteFromTitle(record.title, appName) || appName || "Browser",
      icon: entry ? entry.icon : "",
      glyph: glyphFor("browser")
    }
  }

  return {
    kind: "app",
    name: appName || clean(record.title) || "Window",
    icon: entry ? entry.icon : "",
    glyph: glyphFor("app")
  }
}

// ---------------------------------------------------------------- workspaces

function emptyWorkspace(id) {
  return {
    id: id, number: numberLabel(id), occupied: false, count: 0,
    name: "", kind: "", icon: "", glyph: "", names: [], latest: -1,
    urgent: false, blocked: false, attention: false,
    herdr: false, marks: { working: 0, blocked: 0, done: 0 }
  }
}

function describeWorkspace(id, records, herd, entries) {
  var result = emptyWorkspace(id)
  if (!records || records.length === 0) return result

  var sorted = records.slice().sort(function(a, b) { return recency(b) - recency(a) })
  var seen = ({})
  for (var i = 0; i < sorted.length; i++) {
    var described = describeWindow(sorted[i], herd, entries)
    if (i === 0) {
      result.name = described.name
      result.kind = described.kind
      result.icon = described.icon
      result.glyph = described.glyph
      result.latest = recency(sorted[i])
    }
    if (described.kind === "herdr") result.herdr = true
    if (sorted[i].urgent) result.urgent = true
    if (described.name && !seen[described.name]) {
      seen[described.name] = true
      result.names.push(described.name)
    }
  }

  result.occupied = true
  result.count = sorted.length
  if (result.herdr) {
    result.marks = { working: herd.counts.working, blocked: herd.counts.blocked, done: herd.counts.done }
    result.blocked = herd.counts.blocked > 0
  }
  result.attention = result.urgent || result.blocked
  return result
}

// Every workspace with a positive id that has windows, keyed by id. Call with
// the Quickshell `Hyprland` and `DesktopEntries` singletons and the parsed
// state bus (or null). Look ids up with `workspaceFor`, which fills in empty
// ones.
function collect(hyprland, entries, bus) {
  var herd = herdInfo(bus)
  var toplevels = []
  try { toplevels = hyprland && hyprland.toplevels ? (hyprland.toplevels.values || []) : [] } catch (e) { toplevels = [] }
  var active = hyprland && hyprland.activeToplevel ? hyprland.activeToplevel.address : ""
  if (active) noteFocus(active)

  var byWorkspace = ({})
  var live = ({})
  for (var i = 0; i < toplevels.length; i++) {
    var record = windowRecord(toplevels[i])
    if (!record || !record.address) continue
    live[record.address] = true
    if (!(record.workspaceId > 0)) continue
    if (!byWorkspace[record.workspaceId]) byWorkspace[record.workspaceId] = []
    byWorkspace[record.workspaceId].push(record)
  }
  if (Object.keys(focusRank).length > 64) pruneFocus(live)

  var result = ({})
  for (var id in byWorkspace)
    result[id] = describeWorkspace(Number(id), byWorkspace[id], herd, entries)
  return result
}

function workspaceFor(map, id) {
  return map && map[id] ? map[id] : emptyWorkspace(Number(id))
}

// The workspace number (1-10) a Hyprland workspace id belongs to, or 0.
function numberOf(id) {
  var n = Number(id)
  return n >= 1 && n <= 2 * PAIR_OFFSET ? (n - 1) % PAIR_OFFSET + 1 : 0
}

// Workspace number n with both halves together: named after the most recently
// focused window on either, needing attention if either does.
function pairFor(map, n) {
  var left = workspaceFor(map, n)
  var right = workspaceFor(map, n + PAIR_OFFSET)
  if (!right.occupied) return left
  if (!left.occupied) return Object.assign({}, right, { id: left.id, number: left.number })
  var first = left.latest >= right.latest ? left : right
  var second = first === left ? right : left
  var names = first.names.slice()
  for (var i = 0; i < second.names.length; i++)
    if (names.indexOf(second.names[i]) === -1) names.push(second.names[i])
  return Object.assign({}, first, {
    id: left.id, number: left.number, count: left.count + right.count, names: names,
    urgent: left.urgent || right.urgent, blocked: left.blocked || right.blocked,
    attention: left.attention || right.attention, herdr: left.herdr || right.herdr,
    marks: left.herdr ? left.marks : right.marks
  })
}

// "rat-detective", "rat-detective  +2" when other windows share it.
function tooltipFor(info) {
  if (!info || !info.occupied) return "Workspace " + (info ? info.number : "")
  var text = info.number + "  " + info.name
  if (info.names.length > 1) text += "\n" + info.names.slice(1, 5).join(", ")
  if (info.blocked) text += "\n" + info.marks.blocked + " agent" + (info.marks.blocked === 1 ? "" : "s") + " waiting"
  return text
}
