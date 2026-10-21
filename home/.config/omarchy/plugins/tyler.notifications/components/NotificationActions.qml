import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Flow {
  id: root
  property var actions: []
  property color foreground: Color.popups.text
  property color accent: Color.accent
  signal invoked(string identifier)
  spacing: Style.space(6)
  visible: actions.length > 0

  Repeater {
    model: root.actions
    Controls.Button {
      required property var modelData
      text: modelData.text
      width: Math.min(implicitWidth, root.width)
      padding: Style.space(8)
      onClicked: root.invoked(modelData.identifier)
      contentItem: Text {
        text: parent.text
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
      }
      background: BorderSurface {
        radius: Style.cornerRadius
        color: parent.down ? Style.pressedFillFor(root.foreground, root.accent)
          : Style.controlFill(parent.activeFocus, parent.hovered, root.foreground, root.accent)
        borderSpec: Border.controlSpec(
          parent.activeFocus ? "focus" : (parent.down || parent.hovered ? "hover" : "normal"),
          root.foreground,
          root.accent)
      }
    }
  }
}
