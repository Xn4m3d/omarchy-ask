import QtQuick
import qs.Commons

// The settings screen, shown in place of the composer rather than in a window
// of its own: the card is already the thing that has focus, and a second
// surface would mean a second focus dance for four toggles.
//
// Keyboard-first by design. Every row is a value that cycles, so there is one
// verb (space) instead of one widget vocabulary per setting type.
Column {
  id: root

  property var config: null
  property string agent: ""
  property color foreground: Color.menu.text
  property string fontFamily: Style.font.menuFamily
  property int selectedIndex: 0

  signal closed()

  spacing: Style.spacing.xs

  readonly property var rows: [
    {
      key: "captureWindow",
      label: "capture focused window",
      help: "class and title of the window you came from"
    },
    {
      key: "captureCwd",
      label: "capture working directory",
      help: "for terminals, run the agent in that directory"
    },
    {
      key: "sendMode",
      label: "enter sends",
      help: "inline streams here, terminal opens an agent window"
    },
    {
      key: "agent",
      label: "agent (inline)",
      help: "empty follows omarchy default agent; the terminal path always does"
    },
    {
      key: "reasoningTokens",
      label: "show reasoning",
      help: "ask the agent to think out loud; costs tokens and time"
    },
    {
      key: "animations",
      label: "animations",
      help: "card entrance, activity pulse, streaming cursor"
    },
    {
      key: "inlineTools",
      label: "inline tools",
      help: "tools the inline run may use; it never writes"
    }
  ]

  // Supplied by the card: the agents installed here that it can actually
  // stream from. A fixed list would offer agents this machine does not have,
  // and agents with no adapter -- for which forcing the setting does nothing
  // except make the header name one agent while another answers.
  property var installedAgents: []

  readonly property var agentChoices: [""].concat(root.installedAgents)

  function valueText(key) {
    if (!root.config) return ""
    var v = root.config.get(key)
    if (key === "captureWindow" || key === "captureCwd" || key === "animations")
      return v ? "on" : "off"
    if (key === "reasoningTokens") return Number(v) > 0 ? (Number(v) + " tokens") : "off"
    if (key === "agent") return v ? v : "follow default" + (root.agent ? " (" + root.agent + ")" : "")
    return String(v)
  }

  // One verb for every row: space moves the value on by one. Booleans flip,
  // enums advance, and the two free-text rows say plainly that they are edited
  // in the file — better than a half-built text editor inside a popup.
  function cycle(key) {
    if (!root.config) return
    if (key === "captureWindow" || key === "captureCwd" || key === "animations") {
      root.config.set(key, !root.config.get(key))
    } else if (key === "reasoningTokens") {
      var steps = [0, 4000, 8000, 16000]
      var i = steps.indexOf(Number(root.config.get(key) || 0))
      root.config.set(key, steps[(i + 1) % steps.length])
    } else if (key === "sendMode") {
      root.config.set(key, root.config.get(key) === "inline" ? "terminal" : "inline")
    } else if (key === "agent") {
      var current = String(root.config.get("agent") || "")
      var i = root.agentChoices.indexOf(current)
      root.config.set("agent", root.agentChoices[(i + 1) % root.agentChoices.length])
    }
  }

  function move(delta) {
    var n = root.rows.length
    root.selectedIndex = (root.selectedIndex + delta + n) % n
  }

  function activate() {
    root.cycle(root.rows[root.selectedIndex].key)
  }

  Text {
    text: "settings"
    color: root.foreground
    opacity: 0.5
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    bottomPadding: Style.spacing.xs
  }

  Repeater {
    model: root.rows

    delegate: Rectangle {
      id: row
      required property var modelData
      required property int index

      width: root.width
      implicitHeight: rowLabel.implicitHeight + Style.spacing.xs * 2
      radius: Style.cornerRadius
      color: index === root.selectedIndex ? Style.selectedFill : "transparent"

      MouseArea {
        anchors.fill: parent
        onClicked: {
          root.selectedIndex = row.index
          root.cycle(row.modelData.key)
        }
      }

      Text {
        id: rowLabel
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.label
        color: root.foreground
        opacity: row.index === root.selectedIndex ? 1 : 0.8
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, row.width * 0.5)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideMiddle
        text: root.valueText(row.modelData.key)
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  Text {
    width: root.width
    wrapMode: Text.Wrap
    topPadding: Style.spacing.xs
    text: {
      var r = root.rows[root.selectedIndex]
      if (r.key === "inlineTools")
        return r.help + " — edit ~/.config/omarchy/ask.json to change it"
      return r.help
    }
    color: root.foreground
    opacity: 0.45
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
