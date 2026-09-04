import QtQuick
import qs.Commons

// Past turns, newest first. The point is not nostalgia: each row carries the
// agent session id, so reopening one and pressing Enter continues that
// conversation rather than starting a new one on the same subject.
Item {
  id: root

  property var turns: []
  property int index: 0
  property color foreground: Color.menu.text
  property string fontFamily: Style.font.menuFamily

  signal chosen(int turnIndex)
  signal resumeInTerminal(int turnIndex)

  implicitHeight: layout.implicitHeight

  function move(delta) {
    var n = root.turns.length
    if (n === 0) return
    root.index = (root.index + delta + n) % n
    listView.positionViewAtIndex(root.index, ListView.Contain)
  }

  function activate() {
    if (root.index >= 0 && root.index < root.turns.length) root.chosen(root.index)
  }

  function resume() {
    if (root.index >= 0 && root.index < root.turns.length) root.resumeInTerminal(root.index)
  }

  // Relative time reads faster than a timestamp when everything in the list is
  // from the last few days.
  function ago(ts) {
    var secs = Math.max(0, Math.floor(Date.now() / 1000) - Number(ts || 0))
    if (secs < 60) return "just now"
    var mins = Math.floor(secs / 60)
    if (mins < 60) return mins + "m ago"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + "h ago"
    return Math.floor(hours / 24) + "d ago"
  }

  function oneLine(text) {
    return String(text || "").replace(/\s+/g, " ").trim()
  }

  Column {
    id: layout
    width: parent.width
    spacing: Style.spacing.xs

    Text {
      text: "history"
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      visible: root.turns.length === 0
      text: "nothing asked yet"
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    ListView {
      id: listView
      width: parent.width
      height: Math.min(contentHeight, Style.space(260))
      visible: root.turns.length > 0
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.turns
      currentIndex: root.index

      delegate: Rectangle {
        id: turnRow
        required property var modelData
        required property int index

        width: listView.width
        implicitHeight: turnColumn.implicitHeight + Style.spacing.xs * 2
        radius: Style.cornerRadius
        color: turnRow.index === root.index ? Style.selectedFill : "transparent"

        MouseArea {
          anchors.fill: parent
          onClicked: {
            root.index = turnRow.index
            root.activate()
          }
        }

        Column {
          id: turnColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.spacing.sm
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            width: parent.width
            text: root.oneLine(turnRow.modelData.prompt)
            color: root.foreground
            opacity: turnRow.index === root.index ? 1 : 0.85
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            text: {
              var meta = root.ago(turnRow.modelData.ts)
              if (turnRow.modelData.agent) meta += " · " + turnRow.modelData.agent
              // An entry with no answer is one that was cancelled or died
              // mid-turn. Saying so beats showing a blank second line.
              meta += turnRow.modelData.answer ? "" : " · no answer"
              return meta
            }
            color: root.foreground
            opacity: 0.4
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
