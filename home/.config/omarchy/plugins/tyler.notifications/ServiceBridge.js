.pragma library

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
