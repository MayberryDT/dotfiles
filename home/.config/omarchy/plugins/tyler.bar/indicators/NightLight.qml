import QtQuick
import Quickshell
import qs.Ui

BarIndicator {
  id: root

  readonly property var nightlightService: bar?.shell?.firstPartyServiceFor("omarchy.nightlight")

  // The shell service still applies Omarchy's 4000K. This latch tracks the
  // stronger toggle until that service catches up on its own.
  property bool overrideActive: false
  property bool overridden: false

  active: overridden ? overrideActive : (nightlightService ? nightlightService.enabled : false)
  activeText: "󰔎"
  inactiveText: "󰔎"
  activeTooltipText: "Day Light"
  inactiveTooltipText: "Night Light"

  function toggle() {
    var enabling = !root.active
    root.overrideActive = enabling
    root.overridden = true
    Quickshell.execDetached(["/home/tyler/.local/bin/nightlight-toggle", enabling ? "on" : "off"])
  }

  onPressed: function() { root.toggle() }
}
