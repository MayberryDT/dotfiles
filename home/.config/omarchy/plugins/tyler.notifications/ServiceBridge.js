.pragma library

var sharedService = null
// Live bar chips, one per monitor. The service owns the tyler.notifications
// IPC target (a per-widget handler would only ever reach whichever monitor's
// copy registered first) and routes open/close/toggle to one of these.
var liveWidgets = []

function publish(service) {
  sharedService = service
}

function clear(service) {
  if (sharedService === service) sharedService = null
}

function current() {
  return sharedService
}

function registerWidget(widget) {
  if (!widget || liveWidgets.indexOf(widget) !== -1) return
  liveWidgets = liveWidgets.concat([widget])
}

function unregisterWidget(widget) {
  liveWidgets = liveWidgets.filter(function(item) { return item !== widget })
}

function widgets() {
  return liveWidgets.slice()
}
