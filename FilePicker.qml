import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons

// A keyboard-first file picker, shown in place of the composer.
//
// Built in rather than shelling out to a portal dialog: the card already owns
// keyboard focus, and handing that to a GTK file chooser means a second window,
// a second focus dance, and a theme that does not match. Everything here is a
// list and a filter, which is all attaching a file needs.
Item {
  id: root

  property string startDir: ""
  property color foreground: Color.menu.text
  property string fontFamily: Style.font.menuFamily

  property string dir: ""
  property var entries: []
  property string filter: ""
  property int index: 0
  property bool showHidden: false
  property string error: ""

  signal attached(string path)
  signal cancelled()

  implicitHeight: layout.implicitHeight

  readonly property string homeDir: Quickshell.env("HOME")

  readonly property var visibleEntries: {
    if (!root.filter) return root.entries
    var needle = root.filter.toLowerCase()
    var out = []
    for (var i = 0; i < root.entries.length; i++) {
      if (root.entries[i].name.toLowerCase().indexOf(needle) !== -1)
        out.push(root.entries[i])
    }
    return out
  }

  function prettyPath(path) {
    if (root.homeDir && String(path).indexOf(root.homeDir) === 0)
      return "~" + String(path).substring(root.homeDir.length)
    return path
  }

  function joinPath(base, name) {
    return base === "/" ? "/" + name : base + "/" + name
  }

  function parentOf(path) {
    if (path === "/" || path === "") return "/"
    var i = String(path).lastIndexOf("/")
    if (i <= 0) return "/"
    return String(path).substring(0, i)
  }

  function start() {
    root.dir = root.startDir || root.homeDir
    root.filter = ""
    root.index = 0
    root.load()
  }

  function load() {
    root.error = ""
    var args = ["omarchy-ask-ls", root.dir]
    if (root.showHidden) args.push("--hidden")
    lsProc.command = args
    lsProc.running = true
  }

  function setFilter(next) {
    root.filter = next
    root.index = 0
  }

  function move(delta) {
    var n = root.visibleEntries.length
    if (n === 0) return
    root.index = (root.index + delta + n) % n
    listView.positionViewAtIndex(root.index, ListView.Contain)
  }

  function enterDir(path) {
    root.dir = path
    root.filter = ""
    root.index = 0
    root.load()
  }

  function up() {
    root.enterDir(root.parentOf(root.dir))
  }

  function activate() {
    var list = root.visibleEntries
    if (root.index < 0 || root.index >= list.length) return
    var entry = list[root.index]
    var path = root.joinPath(root.dir, entry.name)
    if (entry.type === "d") root.enterDir(path)
    else root.attached(path)
  }

  function toggleHidden() {
    root.showHidden = !root.showHidden
    root.filter = ""
    root.index = 0
    root.load()
  }

  // Backspace does double duty: trim the filter while there is one, otherwise
  // go up a directory. It reads as one "go back" key rather than two.
  function back() {
    if (root.filter) root.setFilter(root.filter.substring(0, root.filter.length - 1))
    else root.up()
  }

  Process {
    id: lsProc
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i]
          if (!line) continue
          var tab = line.indexOf("\t")
          if (tab === -1) continue
          out.push({ type: line.substring(0, tab), name: line.substring(tab + 1) })
        }
        root.entries = out
        root.index = 0
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim()) root.error = text.trim()
    }
    onExited: function (exitCode) {
      // A directory that cannot be read leaves the previous listing on screen,
      // which would be a lie about where you are. Empty it and say why.
      if (exitCode !== 0) {
        root.entries = []
        if (!root.error) root.error = "cannot read this directory"
      }
    }
  }

  Column {
    id: layout
    width: parent.width
    spacing: Style.spacing.xs

    Text {
      text: "attach a file"
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      text: root.prettyPath(root.dir) + (root.filter ? "  /" + root.filter : "")
      color: Color.accent
      elide: Text.ElideMiddle
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      visible: root.error !== ""
      text: root.error
      color: Color.urgent
      wrapMode: Text.Wrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      visible: root.error === "" && root.visibleEntries.length === 0
      text: root.filter ? "nothing matches" : "empty directory"
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    ListView {
      id: listView
      width: parent.width
      height: Math.min(contentHeight, Style.space(240))
      visible: root.visibleEntries.length > 0
      clip: true
      interactive: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.visibleEntries
      currentIndex: root.index

      delegate: Rectangle {
        id: entryRow
        required property var modelData
        required property int index

        width: listView.width
        implicitHeight: entryLabel.implicitHeight + Style.spacing.xxs * 2
        radius: Style.cornerRadius
        color: entryRow.index === root.index ? Style.selectedFill : "transparent"

        MouseArea {
          anchors.fill: parent
          onClicked: {
            root.index = entryRow.index
            root.activate()
          }
        }

        Row {
          id: entryLabel
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Text {
            text: entryRow.modelData.type === "d" ? "" : ""
            color: entryRow.modelData.type === "d" ? Color.accent : root.foreground
            opacity: entryRow.modelData.type === "d" ? 0.9 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            text: entryRow.modelData.name
            color: root.foreground
            opacity: entryRow.index === root.index ? 1 : 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
