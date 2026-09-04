import Quickshell
import Quickshell.Io
import QtQuick

// Rate-limit state for the current agent.
//
// Read, not fetched. Omarchy already collects this: `omarchy-agent-usage-update`
// runs one collector per agent and writes a normalised record per agent into
// ~/.local/state/omarchy/agents/usage/<id>.json — the same records the
// omarchy.agents bar widget draws. Watching that file costs nothing, works for
// any agent that ships a collector, and never adds an API call of our own.
//
// The live figure from the stream (Claude sends a rate_limit_event mid-turn)
// takes precedence when we have one: it is current, where the file is only as
// fresh as the widget's refresh timer.
Item {
  id: root

  property string agent: ""

  // Set from the stream. -1 means "nothing seen this session".
  property real livePercent: -1
  property string liveWindow: ""

  property var limits: []
  property string tierLabel: ""
  property int todayPrompts: 0

  readonly property string path:
    Quickshell.env("HOME") + "/.local/state/omarchy/agents/usage/" + root.agent + ".json"

  readonly property bool known: root.limits.length > 0 || root.livePercent >= 0

  function pct(value) {
    return Math.round(Math.max(0, Math.min(1, value)) * 100) + "%"
  }

  // "Session (5-hour)" is right for a panel with room; a one-line summary in a
  // composer needs "5h".
  function shortLabel(label) {
    var l = String(label || "")
    if (/5-hour|five_hour|session/i.test(l)) return "5h"
    if (/7-day|weekly|week/i.test(l)) return "7d"
    if (/month/i.test(l)) return "30d"
    return l.toLowerCase()
  }

  // One line, shortest useful form: the live window first when we have it,
  // then whatever windows the record knows about.
  readonly property string summary: {
    var parts = []
    if (root.livePercent >= 0)
      parts.push(root.shortLabel(root.liveWindow) + " " + root.pct(root.livePercent))

    for (var i = 0; i < root.limits.length; i++) {
      var lim = root.limits[i]
      if (typeof lim.percent !== "number") continue
      var label = root.shortLabel(lim.label)
      // Do not print the same window twice when the stream already covered it.
      if (root.livePercent >= 0 && label === root.shortLabel(root.liveWindow)) continue
      parts.push(label + " " + root.pct(lim.percent))
    }
    return parts.join(" · ")
  }

  function load(text) {
    if (!text || !text.trim()) {
      root.limits = []
      root.tierLabel = ""
      return
    }
    try {
      var d = JSON.parse(text)
      root.limits = Array.isArray(d.limits) ? d.limits : []
      root.tierLabel = String(d.tierLabel || "")
      root.todayPrompts = Number(d.todayPrompts || 0)
    } catch (e) {
      root.limits = []
      root.tierLabel = ""
    }
  }

  onAgentChanged: {
    root.limits = []
    root.tierLabel = ""
    root.livePercent = -1
  }

  FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onLoaded: root.load(text())
    // No record simply means this agent has no collector, or has never run.
    // The line disappears; nothing else changes.
    onLoadFailed: root.load("")
    onFileChanged: reload()
  }
}
