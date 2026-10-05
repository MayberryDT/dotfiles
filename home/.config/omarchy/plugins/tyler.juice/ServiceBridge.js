.pragma library

// Hands the singleton tyler.juice service to this plugin's visual entry points.

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
