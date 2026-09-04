import Quickshell
import Quickshell.Io
import QtQuick

// Every turn the composer runs, kept on disk so closing the card is not the
// same as throwing the answer away.
//
// One JSON array rather than an append-only log: the file is capped at `limit`
// turns, so rewriting it whole costs nothing and needs no helper process to
// append. Omarchy keeps its clipboard history the same way.
Item {
  id: root

  readonly property string dir: Quickshell.env("HOME") + "/.local/state/omarchy/ask"
  readonly property string path: root.dir + "/history.json"

  // Enough to find last week's question, small enough that rewriting the file
  // on every turn stays free.
  readonly property int limit: 50

  // Newest first: every consumer here wants the recent end.
  property var turns: []

  readonly property var prompts: {
    var out = []
    for (var i = 0; i < root.turns.length; i++) {
      var p = String(root.turns[i].prompt || "").trim()
      // Consecutive duplicates make the up-arrow feel broken: pressing it
      // twice should move twice.
      if (p && (out.length === 0 || out[out.length - 1] !== p)) out.push(p)
    }
    return out
  }

  function record(turn) {
    var entry = {
      ts: Math.floor(Date.now() / 1000),
      prompt: String(turn.prompt || ""),
      answer: String(turn.answer || ""),
      agent: String(turn.agent || ""),
      cwd: String(turn.cwd || ""),
      sessionId: String(turn.sessionId || ""),
      attachments: turn.attachments || []
    }
    if (!entry.prompt) return

    var next = [entry].concat(root.turns)
    if (next.length > root.limit) next = next.slice(0, root.limit)
    root.turns = next
    file.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // The answer lands after the turn is already recorded, so the newest entry
  // gets patched in place rather than appended a second time.
  function completeLast(answer, sessionId) {
    if (root.turns.length === 0) return
    var next = root.turns.slice()
    var head = {}
    for (var k in next[0]) head[k] = next[0][k]
    head.answer = String(answer || "")
    if (sessionId) head.sessionId = String(sessionId)
    next[0] = head
    root.turns = next
    file.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function clear() {
    root.turns = []
    file.setText("[]\n")
  }

  function load(text) {
    if (!text || !text.trim()) {
      root.turns = []
      return
    }
    try {
      var parsed = JSON.parse(text)
      root.turns = Array.isArray(parsed) ? parsed : []
    } catch (e) {
      // A corrupt history must not take the composer down with it. Starting
      // empty loses the log; refusing to open loses the tool.
      console.warn("ask: could not parse " + root.path + ":", e)
      root.turns = []
    }
  }

  // FileView writes a file, not a tree, and the state directory does not
  // exist on a fresh machine.
  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])

  FileView {
    id: file
    path: root.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.turns = []
    onFileChanged: reload()
  }
}
