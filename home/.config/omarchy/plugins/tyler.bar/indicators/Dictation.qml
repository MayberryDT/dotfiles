import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property string state: "idle"
  property string icon: ""

  active: state === "recording"
  activeText: icon
  inactiveText: "󰍬"
  activeTooltipText: state
  inactiveTooltipText: "Dictate"

  function update(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { return }
    if (data.t !== "recording") return
    state = data.active ? "recording" : "idle"
    if (state === "recording") icon = "󰍬"
    else if (state === "transcribing") icon = "󰔟"
    else icon = ""
  }

  Process {
    command: ["talkify", "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.update(data) }
    }
  }

  onPressed: function() {
    if (!root.bar) return
    root.bar.run("omarchy-shell tornikegomareli.talkify open")
  }
}
