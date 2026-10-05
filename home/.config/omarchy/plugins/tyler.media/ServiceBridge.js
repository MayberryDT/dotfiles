.pragma library

// Hands the singleton tyler.media service to this plugin's bar widgets. The
// cloned bar's shell API is scoped to tyler.bar, so widgets cannot look the
// service up through serviceFor(); both entry points share this library.

var sharedService = null

function publish(service) {
  sharedService = service
}

function clear(service) {
  if (sharedService === service) sharedService = null
}

function current() {
  return sharedService
}
