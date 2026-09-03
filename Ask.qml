import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A composer for the default coding agent, summoned from anywhere.
//
// The shell owns the lifecycle: `open(payloadJson)` on summon, `close()` on
// hide, and `opened` is what toggle() reads to decide which one to call. The
// payload is built by bin/omarchy-ask before the card takes focus — see the
// note there about why the context cannot be collected from in here.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false

  // Context handed over by the wrapper at summon time.
  property string ctxClass: ""
  property string ctxTitle: ""
  property string ctxAddress: ""
  property string ctxCwd: ""

  property string agent: ""

  // Shares the [menu] surface tokens, so a theme that styles the launcher
  // styles this too. Nothing here is a literal color.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily

  readonly property int cardWidth: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)

  readonly property string homeDir: Quickshell.env("HOME")

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    applyPayload(payloadJson)
    root.opened = true
    agentProbe.running = true
    Qt.callLater(function () { input.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "xn4m3d.ask")
  }

  function applyPayload(payloadJson) {
    var p = {}
    try {
      if (payloadJson) p = JSON.parse(payloadJson) || {}
    } catch (e) {
      console.warn("ask: bad payload:", e)
    }
    var w = p.window || {}
    var cls = String(w.class || "")
    // The screensaver and the lock surface are what the compositor reports
    // when they are up, but neither is "what the user was looking at" — the
    // window underneath is, and it is gone from activewindow by then. Better
    // no window context than a confidently wrong one.
    if (cls === "org.omarchy.screensaver" || cls === "org.omarchy.lock") cls = ""

    root.ctxClass = cls
    root.ctxTitle = cls ? String(w.title || "") : ""
    root.ctxAddress = cls ? String(w.address || "") : ""
    root.ctxCwd = String(p.cwd || "")
  }

  // ------------------------------------------------------------ formatting

  // ~/foo reads better than /home/user/foo in a chip that has to stay short.
  function prettyPath(path) {
    if (!path) return ""
    if (root.homeDir && path.indexOf(root.homeDir) === 0)
      return "~" + path.substring(root.homeDir.length)
    return path
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  // The context block mirrors the shape omarchy-agent-crash uses: plain facts
  // under a short heading, so any agent reads it without special handling.
  function composePrompt() {
    var lines = [input.text.trim()]
    var facts = []

    if (root.ctxClass)
      facts.push("  focused window:  " + root.ctxClass + (root.ctxTitle ? " — " + root.ctxTitle : ""))
    if (root.ctxCwd)
      facts.push("  working dir:     " + root.ctxCwd)

    if (facts.length) {
      lines.push("")
      lines.push("Context captured on this Omarchy machine when I asked:")
      lines.push(facts.join("\n"))
    }
    return lines.join("\n")
  }

  function submitToTerminal() {
    var text = input.text.trim()
    if (!text) return
    var prompt = composePrompt()
    var cmd = "omarchy-agent --prompt " + shellQuote(prompt)
    // omarchy-agent redirects to ~/Work when it starts from $HOME, so the
    // captured directory has to be applied before it runs, not after.
    if (root.ctxCwd) cmd = "cd " + shellQuote(root.ctxCwd) + " && " + cmd
    Quickshell.execDetached(["sh", "-lc", cmd])
    input.text = ""
    root.dismiss()
  }

  Process {
    id: agentProbe
    command: ["omarchy-default-agent"]
    stdout: StdioCollector {
      onStreamFinished: root.agent = text.trim()
    }
  }

  // ----------------------------------------------------------------- surface

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-ask"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: layout.implicitHeight + contentTopInset + contentBottomInset
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      // Swallow clicks so hitting the card itself does not dismiss it.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: layout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.md

        // ---------------------------------------------------------- header
        Item {
          width: parent.width
          height: brand.implicitHeight

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Rectangle {
              width: Style.space(6)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Color.accent
            }

            Text {
              id: brand
              text: "ask"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.agent || "no default agent"
            color: root.agent ? Color.accent : root.foreground
            opacity: root.agent ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ----------------------------------------------------------- input
        BorderSurface {
          width: parent.width
          height: Math.max(Style.space(64), input.implicitHeight + Style.spacing.inputPaddingY * 2)
          radius: root.cornerRadius
          color: Style.controlFill(input.activeFocus, false, root.foreground, Color.accent)
          borderSpec: Border.controlSpec(input.activeFocus ? "focus" : "normal", root.foreground, Color.accent)

          TextArea {
            id: input
            anchors.fill: parent
            anchors.margins: Style.spacing.inputPaddingY
            wrapMode: TextArea.Wrap
            placeholderText: "Ask " + (root.agent || "an agent") + "…"
            color: root.foreground
            placeholderTextColor: Qt.darker(root.foreground, 1.6)
            selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            background: null

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Escape) {
                root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Ctrl+Enter inserts a newline; bare Enter and Shift+Enter
                // both send, so the send path is never a surprise.
                if (event.modifiers & Qt.ControlModifier) {
                  input.insert(input.cursorPosition, "\n")
                } else {
                  root.submitToTerminal()
                }
                event.accepted = true
              }
            }
          }
        }

        // ------------------------------------------------------ context row
        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          visible: chipRepeater.count > 0

          Repeater {
            id: chipRepeater
            model: {
              var chips = []
              if (root.ctxClass)
                chips.push({ glyph: "", label: root.ctxClass, hint: root.ctxTitle })
              if (root.ctxCwd)
                chips.push({ glyph: "", label: root.prettyPath(root.ctxCwd), hint: "" })
              return chips
            }

            // Sized from its own content via implicitWidth. Binding `width` to
            // a centered child's implicitWidth instead makes the pill's width
            // depend on a child whose position depends on the pill: Qt breaks
            // the loop by leaving the text overflowing the pill.
            delegate: Rectangle {
              id: chip
              required property var modelData

              implicitWidth: Math.min(chipRow.implicitWidth + Style.spacing.md * 2,
                                      root.cardWidth - Style.spacing.panelPadding * 2)
              implicitHeight: chipRow.implicitHeight + Style.spacing.xs * 2
              radius: root.cornerRadius
              color: Style.normalFill
              border.width: Style.normalBorderWidth
              border.color: Style.normalBorderColor

              Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: Style.spacing.xs

                Text {
                  text: chip.modelData.glyph
                  color: Color.accent
                  opacity: 0.9
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: chip.modelData.label
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                  width: Math.min(implicitWidth, Style.space(260))
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }

        // ---------------------------------------------------------- footer
        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.foreground
          opacity: 0.12
        }

        Row {
          width: parent.width
          spacing: Style.spacing.lg

          Repeater {
            model: [
              { keys: ["enter"], label: "send" },
              { keys: ["ctrl", "enter"], label: "newline" },
              { keys: ["esc"], label: "close" }
            ]

            // RowLayout rather than Row: a key cap is taller than its caption,
            // and only a layout can center the two against each other. Row
            // would top-align them and the captions would ride high.
            delegate: RowLayout {
              id: hint
              required property var modelData
              spacing: Style.spacing.xs

              Repeater {
                model: hint.modelData.keys
                delegate: KeyCap {
                  required property string modelData
                  label: modelData
                  foreground: root.foreground
                  Layout.alignment: Qt.AlignVCenter
                }
              }

              Text {
                text: hint.modelData.label
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                Layout.alignment: Qt.AlignVCenter
              }
            }
          }
        }
      }
    }
  }
}
