import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Flow {
  id: root
  property var actions: []
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
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
      }
      background: BorderSurface {
        radius: Style.cornerRadius
        color: parent.down ? Style.pressedFillFor(Color.foreground, Color.accent)
          : parent.hovered || parent.activeFocus ? Style.hoverFillFor(Color.foreground, Color.accent)
          : Style.normalFillFor(Color.foreground, Color.accent)
        borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      }
    }
  }
}
