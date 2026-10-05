.pragma library

// Shared timing for every juice surface. Import from another plugin with
// `import "../tyler.juice/Motion.js" as Motion`.

var ack = 110       // a press is acknowledged
var settle = 380    // a state settles into place
var drawer = 180    // a drawer opens or closes
var stagger = 28    // delay between items revealed in sequence
var pulse = 1100    // one slow pulse for something significant
var longFade = 900  // a quiet fade out
var breathe = 2600  // one half-cycle of a slow "working" breath

function duration(ms, motion) {
  return motion === "reduced" ? 0 : ms
}
