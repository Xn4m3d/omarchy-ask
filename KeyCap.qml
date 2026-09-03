import QtQuick
import qs.Commons

// A single key rendered as a key, not as prose. Sized from its own label so a
// row of these stays aligned whatever the theme's font scale is.
Rectangle {
  id: root

  property string label: ""
  property color foreground: Color.menu.text

  implicitWidth: text.implicitWidth + Style.spacing.xs * 2
  implicitHeight: text.implicitHeight + Style.spacing.xxs * 2
  radius: Math.max(Style.space(2), Style.cornerRadius)
  color: Style.normalFill
  border.width: Style.normalBorderWidth
  border.color: Style.normalBorderColor

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    color: root.foreground
    opacity: 0.75
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }
}
