import Quickshell
import Quickshell.Io
import QtQuick

// Settings for the ask overlay, kept in ~/.config/omarchy/ask.json.
//
// Deliberately NOT inside the plugin directory: a plugin is a git checkout and
// `omarchy plugin update` fast-forwards it, which would happily walk over a
// config file living there.
//
// Unknown keys in the file are preserved on write, so a config written by a
// newer version of the plugin survives a downgrade.
Item {
  id: root

  readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/ask.json"

  readonly property var defaults: ({
    captureWindow: true,
    captureCwd: true,
    sendMode: "inline",
    agent: "",
    inlineTools: "Read Grep Glob WebFetch WebSearch",
    animations: true,
    reasoningTokens: 0
  })

  property var values: ({})

  function get(key) {
    var v = root.values[key]
    return v === undefined ? root.defaults[key] : v
  }

  function set(key, value) {
    var next = {}
    for (var k in root.values) next[k] = root.values[k]
    next[key] = value
    root.values = next
    file.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function load(text) {
    if (!text || !text.trim()) {
      root.values = {}
      return
    }
    try {
      var parsed = JSON.parse(text)
      root.values = (parsed && typeof parsed === "object") ? parsed : {}
    } catch (e) {
      // A hand-edited file with a stray comma should not take the composer
      // down with it: fall back to defaults and say so in the log.
      console.warn("ask: could not parse " + root.path + ":", e)
      root.values = {}
    }
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.values = ({})
    onFileChanged: reload()
  }
}
