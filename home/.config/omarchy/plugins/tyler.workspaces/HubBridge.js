.pragma library

// The keepLoaded overlay entry (Hub.qml) is the plugin's single instance: it
// owns the IPC target, the peek state and the derived workspace model. Bar
// widgets are not handed a `shell`, so they find it here instead. A
// `.pragma library` script is shared by every importer of this file.

var hub = null

function publish(instance) {
  hub = instance
}

function clear(instance) {
  if (hub === instance) hub = null
}

function current() {
  return hub
}
