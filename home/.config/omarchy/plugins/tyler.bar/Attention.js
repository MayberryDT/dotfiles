.pragma library

// Attention adapters for the bar engine. Each adapter reads the live root item
// of one hosted widget (plain property reads, so a QML binding that calls
// evaluate() re-runs whenever the widget's own state changes) and answers
// { level, reason }:
//   0  nothing to say: the widget may stay folded away in its drawer
//   1  needs a look, or has something new (drawn in accent)
//   2  broken or blocked on you (drawn in urgent)
//
// Any widget can skip the table by exposing `juiceAttention` (0, 1 or 2) and,
// optionally, `juiceAttentionReason` on its root item. Widgets not listed here
// and without that contract never ask to come out of their drawer.
//
// Kept Qt-free so it can be exercised under node.

var NONE = 0
var LOOK = 1
var BROKEN = 2

var QUIET = { level: NONE, reason: "" }

function said(level, reason) {
  return { level: level, reason: String(reason || "") }
}

function count(value) {
  var n = Number(value)
  return isFinite(n) && n > 0 ? Math.floor(n) : 0
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : many)
}

function list(value) {
  return Array.isArray(value) ? value : []
}

function percent(fraction) {
  return Math.round(Number(fraction) * 100) + "%"
}

var adapters = {
  // panels/network/Panel.qml: `kind` is "ethernet" | "wifi" | "disconnected",
  // derived from NetworkManager; `signalStrength` is 0..100 or -1.
  "omarchy.network": function(item) {
    if (item.networkManagerAvailable === false) return QUIET
    if (item.kind === "disconnected") return said(BROKEN, "Offline")
    var signal = Number(item.signalStrength)
    if (item.kind === "wifi" && signal >= 0 && signal < 30) return said(LOOK, "Weak Wi-Fi signal (" + signal + "%)")
    return QUIET
  },

  // panels/audio/Panel.qml: `hasOutput` (a default sink with audio) and
  // `outputMuted`.
  "omarchy.audio": function(item) {
    if (item.hasOutput === false) return said(BROKEN, "No audio output")
    if (item.outputMuted === true) return said(LOOK, "Sound is muted")
    return QUIET
  },

  // panels/power/Panel.qml: `batteryPresent`, `discharging` (on battery) and
  // `batteryFraction` 0..1. Low battery is `urgent` (plan, desktop moments).
  "omarchy.power": function(item) {
    if (item.batteryPresent !== true || item.discharging !== true) return QUIET
    var fraction = Number(item.batteryFraction)
    if (!isFinite(fraction)) return QUIET
    if (fraction <= 0.20) return said(BROKEN, "Battery low: " + percent(fraction))
    return QUIET
  },

  // bar/widgets/SystemUpdate.qml: `updateAvailable` from omarchy-update-available.
  "omarchy.system-update": function(item) {
    return item.updateAvailable === true ? said(LOOK, "Omarchy update available") : QUIET
  },

  // bar/widgets/Indicators.qml: `activeIndicatorIds` lists the indicators that
  // are on (Dictation, ScreenRecording, Reminder, NightLight, Dnd, StayAwake).
  // Night Light is Tyler's normal evening state, not something to look at.
  "omarchy.indicators": function(item) {
    var ids = list(item.activeIndicatorIds).filter(function(id) {
      return String(id || "").toLowerCase().replace(/[^a-z]/g, "") !== "nightlight"
    })
    return ids.length > 0 ? said(LOOK, "On: " + ids.join(", ")) : QUIET
  },

  // bar/widgets/KeyboardLayout.qml exposes only the active keymap's name, so
  // the engine reads the layout index itself (ctx.keyboard, from hyprctl, asked
  // again each time the widget's `layoutFull` changes). First layout = default.
  "omarchy.keyboard-layout": function(item, ctx) {
    var keyboard = ctx && ctx.keyboard
    if (!keyboard || !(Number(keyboard.index) > 0)) return QUIET
    return said(LOOK, "Keyboard layout: " + String(item.layoutFull || keyboard.keymap || "not the default"))
  },

  // bar/widgets/Tray.qml: `allItems` are SystemTrayItems; status NeedsAttention.
  "omarchy.tray": function(item, ctx) {
    var wanted = ctx ? ctx.trayNeedsAttention : undefined
    if (wanted === undefined) return QUIET
    var items = list(item.allItems)
    for (var i = 0; i < items.length; i++) {
      var tray = items[i]
      if (tray && tray.status === wanted)
        return said(LOOK, String(tray.title || tray.tooltipTitle || tray.id || "A tray app") + " wants attention")
    }
    return QUIET
  },

  // agents/Panel.qml: `providers` plus its own bindingWindow(p) (fullest limit
  // window, percent 0..1). The widget alarms at 90% or a prepaid balance in its
  // last 10%; the engine uses the same line across every provider.
  "omarchy.agents": function(item) {
    var providers = list(item.providers)
    var best = null
    var bestName = ""
    for (var i = 0; i < providers.length; i++) {
      var provider = providers[i]
      if (!provider) continue
      var name = String(provider.displayName || provider.name || provider.providerId || "AI")
      var window = typeof item.bindingWindow === "function" ? item.bindingWindow(provider) : null
      if (window && isFinite(Number(window.percent)) && (!best || window.percent > best.percent)) {
        best = window
        bestName = name
      }
      var balance = provider.balance
      if (balance && balance.funded > 0 && balance.remaining / balance.funded <= 0.1)
        return said(LOOK, name + " credit nearly spent")
    }
    if (!best) return QUIET
    if (best.percent >= 1) return said(BROKEN, bestName + " " + String(best.title || "limit").toLowerCase() + " limit reached")
    if (best.percent >= 0.9) return said(LOOK, bestName + " " + String(best.title || "limit").toLowerCase() + " at " + percent(best.percent))
    return QUIET
  },

  // nixfred.pulse/Panel.qml: `worst` is the section with the least headroom;
  // `concern` 0..1 against its own Constraints.HIGH (0.85, "acting on now").
  // A stale section (collector offline) is pulse's own problem, not the
  // machine's, so it stays folded away.
  "nixfred.pulse": function(item) {
    var worst = item.worst
    if (!worst || worst.stale === true) return QUIET
    if (!(Number(worst.concern) >= 0.85)) return QUIET
    return said(LOOK, String(worst.sectionTitle || "System") + " " + String(worst.headline || "under pressure"))
  },

  // io.github.nixfred.tailscale-host-monitor/Panel.qml: `barState` is
  // "pass" | "warn" | "fail" over the watched hosts.
  "io.github.nixfred.tailscale-host-monitor": function(item) {
    if (item.barState === "fail") return said(BROKEN, "A watched host is down")
    if (item.barState === "warn") return said(LOOK, "A watched host has a warning")
    return QUIET
  },

  // ---- launchers: news only ----

  // omaplug/BarWidget.qml: `pendingUpdateCount`.
  "omaplug": function(item) {
    var n = count(item.pendingUpdateCount)
    return n > 0 ? said(LOOK, plural(n, "plugin update", "plugin updates")) : QUIET
  },

  // omamail/ui/BarWidget.qml: `gmail.unreadTotal` (service or bridge snapshot).
  "omamail": function(item) {
    var n = item.gmail ? count(item.gmail.unreadTotal) : 0
    return n > 0 ? said(LOOK, plural(n, "unread email", "unread emails")) : QUIET
  },

  // com.omastorm.radar/ui/RadarBar.qml: the widget's own dots are `down`
  // (feed offline or unavailable) and `session.updatePending`.
  "com.omastorm.radar": function(item) {
    var state = item.state
    var status = state && state.connection ? String(state.connection.status || "") : ""
    if (status === "offline" || status === "unavailable") return said(BROKEN, "Radar feed is down")
    if (item.session && item.session.updatePending === true) return said(LOOK, "Radar update waiting")
    return QUIET
  },

  // co.animasai.rat-detective/BarWidget.qml: `humanCount`, alerting at the
  // widget's own `alertHumanThreshold` setting unless alerts are off.
  "co.animasai.rat-detective": function(item) {
    var settings = item.settings || {}
    if (settings.alertsEnabled === false) return QUIET
    var threshold = Math.max(1, count(settings.alertHumanThreshold) || 1)
    var n = count(item.humanCount)
    return n >= threshold ? said(LOOK, plural(n, "investigator", "investigators") + " online") : QUIET
  },

  // io.zet.ibara/BarWidget.qml: `needsCount` (approvals, questions, computers
  // that need you: blocked on you) and `problems` (offline or stuck computers).
  "io.zet.ibara": function(item) {
    if (item.stopped === true) return QUIET
    var needs = count(item.needsCount)
    if (needs > 0) return said(BROKEN, plural(needs, "thing waits", "things wait") + " for you")
    var problems = list(item.problems).length
    if (problems > 0) return said(LOOK, plural(problems, "computer needs", "computers need") + " attention")
    return QUIET
  }
}

function hasAdapter(id) {
  return Object.prototype.hasOwnProperty.call(adapters, String(id || ""))
}

function evaluate(id, item, ctx) {
  if (!item) return QUIET
  var best = QUIET
  var adapter = adapters[String(id || "")]
  if (adapter) {
    try {
      best = adapter(item, ctx) || QUIET
    } catch (e) {
      best = QUIET
    }
  }
  var declared = Number(item.juiceAttention)
  if (isFinite(declared) && declared > best.level) {
    best = said(Math.min(BROKEN, Math.floor(declared)), item.juiceAttentionReason || "")
  }
  return best
}

// A calendar event counts as a meeting while it is running, is timed, was not
// declined, and involves someone else: it carries a meeting link or an RSVP
// (Google only reports a response status when there are attendees). A block
// Tyler put in his own calendar has neither and does not start meeting mode.
// Events follow tmn73.calendar's contract (~/.local/state/omarchy/calendar-events.json).
function meetingNow(events, nowMs) {
  var rows = list(events)
  for (var i = 0; i < rows.length; i++) {
    var event = rows[i]
    if (!event || event.allDay) continue
    var start = Date.parse(event.start)
    var end = Date.parse(event.end)
    if (!isFinite(start) || !isFinite(end) || !(start <= nowMs && nowMs < end)) continue
    var response = String(event.responseStatus || "")
    if (response === "declined") continue
    if (String(event.meetingUrl || "") !== "" || response !== "") return event
  }
  return null
}

// fake-attention.json: { "<widget id>": 0|1|2, "@meeting": true, "@focus": true,
// "@away": true }. Anything else is ignored.
function parseFake(text) {
  var out = { levels: {}, meeting: false, focus: false, away: false }
  var data = null
  try {
    data = JSON.parse(String(text || "") || "{}")
  } catch (e) {
    return out
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return out
  for (var key in data) {
    var value = data[key]
    if (key === "@meeting") out.meeting = value === true
    else if (key === "@focus") out.focus = value === true
    else if (key === "@away") out.away = value === true
    else if (key.charAt(0) !== "@") {
      var level = Number(value)
      if (isFinite(level) && level > 0) out.levels[key] = Math.min(BROKEN, Math.floor(level))
    }
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    NONE: NONE,
    LOOK: LOOK,
    BROKEN: BROKEN,
    evaluate: evaluate,
    hasAdapter: hasAdapter,
    meetingNow: meetingNow,
    parseFake: parseFake
  }
}
