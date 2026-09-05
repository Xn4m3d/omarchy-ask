import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "agents.js" as Agents

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
  property string ctxGeometry: ""

  // Explicitly attached files: [{ kind, path, label }]. Nothing lands here
  // without a keystroke — a clipboard that quietly ships with every question
  // is a password waiting to be sent somewhere.
  property var attachments: []

  // While a capture runs the card steps off screen, because it is an
  // Overlay-layer surface and would otherwise be the thing photographed.
  property bool capturing: false

  property string agent: ""
  property string notice: ""

  // Inline run state: "idle" | "running" | "done" | "error".
  property string runState: "idle"

  // Whether the current run has written anything at all. It is the only
  // safe basis for declaring a run dead on a timer: a live agent prints
  // something within seconds, and a run that has been silent from the start
  // never started at all.
  property bool sawOutput: false
  property string answer: ""

  // The question this answer belongs to. It moves out of the input and above
  // the answer on send, so the box is empty and ready for a follow-up while
  // you can still see what was asked.
  property string askedPrompt: ""
  property string thinking: ""
  property string status: ""
  property string sessionId: ""
  property bool settingsOpen: false
  property bool pickerOpen: false
  property bool historyOpen: false

  // -1 means "typing", not "browsing". Up-arrow walks it forward through
  // history.prompts and Down walks it back to -1.
  property int historyIndex: -1
  property string draftBeforeHistory: ""

  // The configured agent wins over the system default when set; empty means
  // "whatever omarchy default agent says", which is the shipped behaviour.
  readonly property string effectiveAgent: {
    var forced = String(config.get("agent") || "")
    return forced ? forced : root.agent
  }
  readonly property bool inlineAvailable: Agents.supportsInline(root.effectiveAgent)

  // The agents actually installed on this machine, in cycle order. Empty until
  // the detector answers, which is why the switch is offered only once it has
  // more than one name to offer.
  property var installedAgents: []

  // What the agent running this session has already been told. A follow-up
  // goes out with --resume, so the context block and the attachment paths are
  // things it already has.
  property bool contextSent: false
  property var attachmentsSent: []
  readonly property bool canSwitchAgent: root.installedAgents.length > 1

  property string model: ""
  property bool thinkingOpen: false

  Config { id: config }
  History { id: history }
  Usage { id: usage; agent: root.effectiveAgent }

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

  // The answer grows the card, but never past half the screen: past that it
  // stops being a glance and starts being a window, which is what Shift+Enter
  // is for.
  readonly property int maxAnswerHeight: Math.round(panel.height * 0.5)

  // 0 closed, 1 open. Animating a number rather than toggling `visible`
  // directly is what makes the exit visible at all: the window has to outlive
  // the close by the length of the animation.
  //
  // 140ms / OutCubic is Omarchy's own tempo — it is the duration the shell
  // uses most, and Ui/PopupCard.qml fades on exactly these numbers. Matching
  // it matters more than picking something nicer in isolation.
  readonly property bool animate: config.get("animations") !== false
  property real reveal: (root.opened && !root.capturing) ? 1 : 0

  Behavior on reveal {
    // Never animate the way out of a screen capture: the helper waits a fixed
    // 150ms for the surface to be gone, and a fade would still be on screen —
    // straight back to photographing our own card.
    enabled: root.animate && !root.capturing
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  readonly property string homeDir: Quickshell.env("HOME")

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    var p = {}
    try {
      if (payloadJson) p = JSON.parse(payloadJson) || {}
    } catch (e) {}

    // Closing the card does not cancel the agent, so a summon that lands while
    // a turn is still being written puts you back in front of it instead of
    // discarding work you already paid for.
    if (root.runState === "running") {
      root.opened = true
      Qt.callLater(function () { root.focusActiveSurface() })
      return
    }

    // Reopening on a finished turn, from the notification or `omarchy-ask
    // --last`: show the answer rather than an empty box.
    if (p.restore === "last" && history.turns.length > 0) {
      root.showTurn(0)
      root.opened = true
      agentProbe.running = true
      Qt.callLater(function () { root.focusActiveSurface() })
      return
    }

    applyPayload(payloadJson)
    root.resetComposer()
    root.opened = true
    agentProbe.running = true
    Qt.callLater(function () { root.focusActiveSurface() })
  }

  // A fresh question is a fresh conversation: dropping the session id is what
  // stops the previous topic from leaking into an unrelated one.
  function resetComposer() {
    root.attachments = []
    root.notice = ""
    root.sessionId = ""
    root.contextSent = false
    root.attachmentsSent = []
    root.answer = ""
    root.thinking = ""
    root.status = ""
    root.runState = "idle"
    root.historyIndex = -1
    root.askedPrompt = ""
    input.text = ""
  }

  // Load a recorded turn back into the card, session id included, so Enter
  // continues that conversation instead of starting a new one.
  function showTurn(index) {
    if (index < 0 || index >= history.turns.length) return
    var t = history.turns[index]
    root.settingsOpen = false
    root.pickerOpen = false
    root.historyOpen = false
    // The recalled question goes above the answer, not back into the box:
    // reopening a turn is for continuing it, and a box pre-filled with the
    // question you already asked makes Enter re-ask it.
    root.askedPrompt = String(t.prompt || "")
    input.text = ""
    root.answer = String(t.answer || "")
    root.sessionId = String(t.sessionId || "")
    // That session was given its context on the turn being recalled, so
    // continuing it does not repeat the block.
    root.contextSent = root.sessionId !== ""
    root.attachmentsSent = []
    root.ctxCwd = String(t.cwd || "")
    root.attachments = []
    root.status = ""
    root.runState = t.answer ? "done" : "idle"
    Qt.callLater(function () { root.focusActiveSurface() })
  }

  function close() {
    root.opened = false
    // Sub-views do not survive a close. Reopening lands on the composer, the
    // one state where every key does what the footer says it does.
    root.historyOpen = false
    root.pickerOpen = false
    root.settingsOpen = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "xn4m3d.ask")
  }

  // Whichever surface is showing owns the keyboard. Routing focus through one
  // place is what keeps a sub-view from being visible while a hidden TextArea
  // holds the focus — the card looks alive and answers nothing.
  function focusActiveSurface() {
    if (root.historyOpen) historyKeys.forceActiveFocus()
    else if (root.pickerOpen) pickerKeys.forceActiveFocus()
    else if (root.settingsOpen) settingsKeys.forceActiveFocus()
    else input.forceActiveFocus()
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

    // Settings are applied here, at the point of use, rather than in the
    // wrapper: collecting is cheap and lossless, and it keeps --print-context
    // honest about what the machine can see regardless of preferences.
    var wantWindow = config.get("captureWindow")
    var wantCwd = config.get("captureCwd")

    root.ctxClass = wantWindow ? cls : ""
    root.ctxTitle = (wantWindow && cls) ? String(w.title || "") : ""
    root.ctxAddress = (wantWindow && cls) ? String(w.address || "") : ""
    root.ctxGeometry = (wantWindow && cls) ? String(w.geometry || "") : ""
    root.ctxCwd = wantCwd ? String(p.cwd || "") : ""
  }

  // ----------------------------------------------------------- attachments

  function basename(path) {
    var i = String(path).lastIndexOf("/")
    return i === -1 ? String(path) : String(path).substring(i + 1)
  }

  // A chip saying "window shot" is worth more than one saying
  // "window-20260903-221053-017.png": the timestamped filename is an
  // implementation detail, and the user already knows which key they pressed.
  function attachmentLabel(kind, path) {
    if (kind === "window") return "window shot"
    if (kind === "region") return "region shot"
    if (kind === "clipboard")
      return String(path).slice(-4) === ".txt" ? "clipboard text" : "clipboard image"
    return root.basename(path)
  }

  function addAttachment(kind, path) {
    var next = root.attachments.slice()
    next.push({ kind: kind, path: path, label: root.attachmentLabel(kind, path) })
    root.attachments = next
  }

  function removeAttachment(index) {
    if (index < 0 || index >= root.attachments.length) return
    var next = root.attachments.slice()
    next.splice(index, 1)
    root.attachments = next
  }

  function flash(message) {
    root.notice = message
    noticeTimer.restart()
  }

  // Capture modes that photograph the screen have to run with the card
  // hidden. Hiding a layer surface drops its keyboard focus, so it has to be
  // taken back once the capture is done or the composer goes deaf.
  function runCapture(kind, args) {
    if (root.capturing) return
    root.capturing = true
    captureProc.kind = kind
    captureProc.command = args
    captureProc.running = true
  }

  function captureWindow() {
    if (!root.ctxGeometry) {
      root.flash("no window to capture")
      return
    }
    runCapture("window", ["omarchy-ask-capture", "window", root.ctxGeometry])
  }

  function captureRegion() {
    runCapture("region", ["omarchy-ask-capture", "region"])
  }

  function attachClipboard() {
    runCapture("clipboard", ["omarchy-ask-capture", "clipboard"])
  }

  Timer {
    id: noticeTimer
    interval: 2500
    onTriggered: root.notice = ""
  }

  Process {
    id: captureProc
    property string kind: ""
    property string result: ""

    stdout: StdioCollector {
      onStreamFinished: captureProc.result = text.trim()
    }

    onExited: function (exitCode) {
      var path = captureProc.result
      captureProc.result = ""
      root.capturing = false

      if (exitCode === 0 && path) root.addAttachment(captureProc.kind, path)
      // A cancelled region pick and an empty clipboard both land here. Neither
      // is an error worth a dialog, but silence would read as a broken key.
      else if (captureProc.kind === "clipboard") root.flash("clipboard is empty")
      else if (exitCode !== 0) root.flash("capture cancelled")

      Qt.callLater(function () { root.focusActiveSurface() })
    }
  }

  // ------------------------------------------------------------ formatting

  // "claude-opus-5" in a corner is mostly the word "claude" again, which the
  // line already says. Keep the half that actually varies.
  function shortModel(id) {
    var m = String(id || "")
    m = m.replace(/^(claude|grok|gpt|gemini)[-_]/, "")
    m = m.replace(/-\d{8}$/, "")
    return m
  }

  // ~/foo reads better than /home/user/foo in a chip that has to stay short.
  function prettyPath(path) {
    if (!path) return ""
    if (root.homeDir && path.indexOf(root.homeDir) === 0)
      return "~" + path.substring(root.homeDir.length)
    return path
  }

  // The shell already ships this; a second copy of a quoting routine is a
  // second place for it to be subtly wrong.
  function shellQuote(value) {
    return Util.shellQuote(value)
  }

  function copyAnswer() {
    if (!root.answer) return
    // Same shape Omarchy uses for its own copy actions (network and tailscale
    // panels), so there is one clipboard idiom on this desktop, not two.
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(root.answer) + " | wl-copy"])
    root.flash("answer copied")
  }

  // The context block mirrors the shape omarchy-agent-crash uses: plain facts
  // under a short heading, so any agent reads it without special handling.
  // `full` forces the whole context block. The terminal path needs it every
  // time -- it starts a brand new agent that knows nothing -- while an inline
  // follow-up resumes a session that was already told all of this.
  //
  // Repeating it would not just waste tokens restating the window and the
  // directory. "Read the attached files listed above" repeated on every turn
  // makes the agent read them again on every turn, and for a screenshot or a
  // large file that is a real bill for no new information. Worse, it drags a
  // follow-up as short as "why?" back to the attachment instead of the answer.
  function composePrompt(full) {
    var lines = [input.text.trim()]
    var facts = []

    var continuing = !full && root.sessionId !== "" && root.contextSent

    if (!continuing) {
      if (root.ctxClass)
        facts.push("  focused window:  " + root.ctxClass + (root.ctxTitle ? " — " + root.ctxTitle : ""))
      if (root.ctxCwd)
        facts.push("  working dir:     " + root.ctxCwd)
    }

    // Attachments travel as paths, not as an upload protocol: every agent can
    // already read a file it is pointed at, so this stays agent-agnostic.
    // Anything attached since the last turn still has to be announced, even
    // mid-conversation -- that is the whole point of attaching it now.
    var fresh = 0
    for (var i = 0; i < root.attachments.length; i++) {
      var a = root.attachments[i]
      if (continuing && root.attachmentsSent.indexOf(a.path) >= 0) continue
      facts.push("  attached (" + a.kind + "):  " + a.path)
      fresh++
    }

    if (facts.length) {
      lines.push("")
      lines.push(continuing
                 ? "Also attached on this Omarchy machine:"
                 : "Context captured on this Omarchy machine when I asked:")
      lines.push(facts.join("\n"))
      if (fresh)
        lines.push("\nRead the attached files listed above before answering.")
    }
    return lines.join("\n")
  }

  // Called once a turn has actually been handed to the agent: from here on,
  // this session has the context and these attachments.
  function markContextSent() {
    root.contextSent = true
    var paths = []
    for (var i = 0; i < root.attachments.length; i++) paths.push(root.attachments[i].path)
    root.attachmentsSent = paths
  }

  // ------------------------------------------------------------- inline run

  function submitInline() {
    var text = input.text.trim()
    if (!text || root.runState === "running") return

    var adapter = Agents.forAgent(root.effectiveAgent)
    // No adapter means no way to read this agent's output. Falling back to the
    // terminal beats an empty card that never fills in.
    if (!adapter) {
      root.submitToTerminal()
      return
    }

    root.answer = ""
    root.thinking = ""
    root.thinkingOpen = false
    root.status = "thinking"
    root.runState = "running"

    // Recorded before the run, not after: a turn that never finishes is
    // exactly the one worth being able to find again.
    history.record({
      prompt: text,
      agent: root.effectiveAgent,
      cwd: root.ctxCwd,
      sessionId: root.sessionId,
      attachments: root.attachments
    })

    runProc.adapter = adapter
    runProc.command = adapter.argv({
      prompt: root.composePrompt(false),
      cwd: root.ctxCwd,
      sessionId: root.sessionId,
      allowedTools: String(config.get("inlineTools") || Agents.READ_ONLY_TOOLS),
      reasoningTokens: Number(config.get("reasoningTokens") || 0)
    })
    // Assigned every run, never conditionally: workingDirectory persists on
    // the Process, so a stale one would quietly follow the next question into
    // a directory that has nothing to do with it.
    runProc.workingDirectory = root.ctxCwd
    root.sawOutput = false
    runProc.running = true

    // Only after argv is built: composePrompt() reads the box.
    root.markContextSent()
    root.askedPrompt = text
    input.text = ""
    root.historyIndex = -1
  }

  // Focus has to be handed over explicitly: the composer and the settings
  // list are two different key handlers, and a hidden TextArea keeps nothing.
  function toggleSettings() {
    root.settingsOpen = !root.settingsOpen
    Qt.callLater(function () { root.focusActiveSurface() })
  }

  // Up-arrow recalls previous prompts, the way a shell does — but only from
  // the first line of the box. Below that, Up has to stay "move the cursor up"
  // or a multi-line question becomes uneditable.
  function cursorOnFirstLine() {
    return input.text.substring(0, input.cursorPosition).indexOf("\n") === -1
  }

  function cursorOnLastLine() {
    return input.text.substring(input.cursorPosition).indexOf("\n") === -1
  }

  function recallPrompt(delta) {
    var list = history.prompts
    if (list.length === 0) return false

    var next = root.historyIndex + delta
    if (next < -1) next = -1
    if (next >= list.length) next = list.length - 1
    if (next === root.historyIndex) return true

    // Stash whatever was being typed on the way into history, and hand it
    // back on the way out. Losing a half-written question to a stray arrow
    // key is the thing that makes people stop trusting history.
    if (root.historyIndex === -1 && next >= 0)
      root.draftBeforeHistory = input.text

    root.historyIndex = next
    input.text = next === -1 ? root.draftBeforeHistory : list[next]
    input.cursorPosition = input.text.length
    return true
  }

  function toggleHistory() {
    root.historyOpen = !root.historyOpen
    if (root.historyOpen) historyView.index = 0
    Qt.callLater(function () { root.focusActiveSurface() })
  }

  // Hand a recorded session to a real terminal. The agent's own --resume is
  // what makes this a continuation rather than a re-ask, so an entry without a
  // session id gets the prompt back instead of a broken resume.
  function resumeTurnInTerminal(index) {
    if (index < 0 || index >= history.turns.length) return
    var t = history.turns[index]
    var agentName = String(t.agent || root.agent)
    var cmd

    if (t.sessionId && (agentName === "claude" || agentName === "grok")) {
      cmd = agentName + " --resume " + shellQuote(t.sessionId)
    } else {
      cmd = "omarchy-agent --prompt " + shellQuote(String(t.prompt || ""))
    }
    if (t.cwd) cmd = "cd " + shellQuote(t.cwd) + " && " + cmd

    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.agent", "sh", "-lc", cmd])
    root.historyOpen = false
    root.dismiss()
  }

  function togglePicker() {
    root.pickerOpen = !root.pickerOpen
    if (root.pickerOpen) {
      // Start where the question came from: attaching a file from the project
      // you were just looking at is the common case by a wide margin.
      filePicker.startDir = root.ctxCwd || Quickshell.env("HOME")
      filePicker.start()
    }
    Qt.callLater(function () { root.focusActiveSurface() })
  }

  // Called once a turn stops, however it stopped. Persists the answer, and
  // says so out loud when the card is closed — otherwise an answer that
  // arrives after you walked away is an answer nobody ever reads.
  function finishTurn() {
    history.completeLast(root.answer, root.sessionId)
    if (!root.opened && root.answer) {
      var preview = root.answer.replace(/\s+/g, " ").trim()
      if (preview.length > 120) preview = preview.substring(0, 119) + "…"
      Quickshell.execDetached([
        "omarchy-notification-send",
        "Ask answered",
        preview,
        "--exec", "omarchy-ask", "--last"
      ])
    }
  }

  function cancelRun() {
    if (root.runState !== "running") return
    runProc.running = false
    root.runState = "done"
    root.status = "cancelled"
    // Keep whatever had already been written: a half answer is still an
    // answer, and it cost the same to produce.
    history.completeLast(root.answer, root.sessionId)
  }

  // A follow-up reuses the session id the agent handed back, so the card keeps
  // one conversation rather than starting a fresh one on every question.
  function askAgain() {
    root.submitInline()
  }

  // Move to the next installed agent. This writes the plugin's own setting and
  // never touches `omarchy default agent`: the rest of the desktop keeps the
  // agent it was told to use, and the card remembers the one you last picked
  // here. The settings panel is still the way back to "follow the default".
  function cycleAgent(delta) {
    var list = root.installedAgents
    if (list.length < 2) return

    var at = list.indexOf(root.effectiveAgent)
    var next = list[(((at < 0 ? 0 : at + delta) % list.length) + list.length) % list.length]
    if (next === root.effectiveAgent) return

    config.set("agent", next)

    // A session id belongs to the agent that issued it. Carrying one across a
    // switch would ask the new agent to resume a conversation it never had,
    // so the next question starts a fresh one -- context block included.
    root.sessionId = ""
    root.contextSent = false
    root.attachmentsSent = []
    root.model = ""
  }

  // Which agents exist here is a fact about the machine, not about this run:
  // read once when the card is built, not on every open.
  Process {
    id: agentsProc
    running: true
    command: ["omarchy-ask-agents"]
    stdout: StdioCollector {
      onStreamFinished: {
        // Installed AND streamable here. Offering an agent with no adapter
        // would be a trap: Enter would quietly fall back to the terminal, and
        // the terminal path runs `omarchy-agent`, which takes no agent
        // argument and launches the Omarchy default -- so the card would name
        // one agent while a different one answered.
        var found = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (name && Agents.supportsInline(name)) found.push(name)
        }
        root.installedAgents = found
      }
    }
  }

  // Quickshell's Process exposes `started` and `exited` and nothing else: a
  // spawn that fails outright -- an unreadable working directory, a binary
  // that is not on PATH -- emits neither, and the card would sit on
  // "thinking..." waiting for output that is never coming. This is the floor
  // under that. It is deliberately generous: it exists to make a wedged card
  // impossible, not to put a deadline on a slow answer.
  Timer {
    interval: 45000
    running: root.runState === "running" && !root.sawOutput
    onTriggered: {
      if (root.runState !== "running" || root.sawOutput) return
      runProc.running = false
      root.answer = root.effectiveAgent + " produced no output. It may not have "
                  + "been able to start"
                  + (root.ctxCwd ? " in " + root.ctxCwd : "") + "."
      root.runState = "error"
      root.status = ""
      root.finishTurn()
    }
  }

  Process {
    id: runProc
    property var adapter: null

    stdout: SplitParser {
      onRead: function (line) {
        // Before the adapter, and whatever it makes of the line: any byte on
        // stdout proves the process exists, which is all the guard below asks.
        root.sawOutput = true
        if (!runProc.adapter) return
        var ev = runProc.adapter.parse(line)
        if (!ev) return

        if (ev.kind === "session") {
          root.sessionId = ev.sessionId
        } else if (ev.kind === "model") {
          root.model = ev.text
        } else if (ev.kind === "rate") {
          usage.livePercent = ev.percent
          usage.liveWindow = ev.window
        } else if (ev.kind === "break") {
          // Only between blocks, never before the first one.
          if (root.answer) root.answer += "\n\n"
        } else if (ev.kind === "delta") {
          root.answer += ev.text
          root.status = ""
        } else if (ev.kind === "thinking") {
          root.thinking += ev.text
          root.status = "thinking"
        } else if (ev.kind === "tool") {
          root.status = ev.text
        } else if (ev.kind === "done") {
          // Some turns never emit deltas (a short answer can arrive whole).
          // The final result is the fallback, not the primary path.
          if (!root.answer && ev.text) root.answer = ev.text
          if (ev.sessionId) root.sessionId = ev.sessionId
          root.status = ""
          root.runState = "done"
          root.finishTurn()
        } else if (ev.kind === "error") {
          root.answer = ev.text
          root.runState = "error"
          root.status = ""
          root.finishTurn()
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        // Only surface stderr when nothing else explained the failure: agents
        // write warnings there on perfectly good runs.
        if (root.runState === "running" && text.trim()) {
          root.answer = text.trim()
          root.runState = "error"
        }
      }
    }

    onExited: function (exitCode) {
      if (root.runState !== "running") return
      root.runState = exitCode === 0 ? "done" : "error"
      if (exitCode !== 0 && !root.answer)
        root.answer = "The agent exited with code " + exitCode + "."
      root.status = ""
      root.finishTurn()
    }
  }

  function submitToTerminal() {
    var text = input.text.trim()
    if (!text) return
    // Always the full block: this opens a new agent, which has been told
    // nothing, whatever the card has already sent inline.
    var prompt = composePrompt(true)
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
    // Outlives `opened` so the exit animation has something to draw on.
    visible: (root.opened && !root.capturing) || root.reveal > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-ask"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: root.reveal
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

      // Switching to settings or the picker resizes the card; easing that is
      // the difference between "another view" and "it jumped". Never while an
      // answer streams, though: the height changes on nearly every delta, and
      // easing each one turns a growing card into a wobbling one.
      Behavior on height {
        enabled: root.animate && root.runState !== "running" && root.reveal > 0.99
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
      anchors.centerIn: parent

      // Small numbers on purpose. A card that flies in from far away reads as
      // slow the second time you see it; 3% and 10px read as "it landed".
      opacity: root.reveal
      scale: 0.97 + 0.03 * root.reveal
      anchors.verticalCenterOffset: Math.round((1 - root.reveal) * Style.space(10))
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

            // The identity mark doubles as the activity light. A separate
            // spinner would be a second thing to look at; this is already
            // where the eye lands.
            Rectangle {
              id: brandDot
              width: Style.space(6)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Color.accent

              SequentialAnimation on opacity {
                running: root.runState === "running" && root.animate
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.25; duration: 620; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutSine }
              }

              // The loop leaves opacity wherever it stopped, so put it back.
              onOpacityChanged: if (root.runState !== "running" && opacity !== 1) opacity = 1
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

          Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              anchors.right: parent.right
              // The model only shows once the agent has said which one it is,
              // so the line never claims something it has not been told.
              text: {
                var name = root.effectiveAgent || "no default agent"

                // Forced to an agent this card cannot stream -- only reachable
                // from the settings list. Enter goes to a terminal, and the
                // terminal runs the Omarchy default. Say so, rather than
                // printing a name that will not be the one answering.
                if (root.effectiveAgent && !root.inlineAvailable) {
                  name += " → terminal"
                  if (root.agent && root.agent !== root.effectiveAgent)
                    name += " · " + root.agent
                  return name
                }

                if (root.model) name += " · " + root.shortModel(root.model)
                return name
              }
              color: root.effectiveAgent ? Color.accent : root.foreground
              opacity: root.effectiveAgent ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption

              // The name of the agent is also the control that changes it.
              // Nothing else in the header is clickable, so this needs no
              // affordance beyond the cursor.
              MouseArea {
                anchors.fill: parent
                enabled: root.canSwitchAgent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function (mouse) {
                  root.cycleAgent(mouse.button === Qt.RightButton ? -1 : 1)
                }
              }
            }

            Text {
              anchors.right: parent.right
              visible: usage.known
              text: usage.summary + (usage.tierLabel ? " · " + usage.tierLabel : "")
              color: root.foreground
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // --------------------------------------------------------- history
        Item {
          id: historyKeys
          width: parent.width
          visible: root.historyOpen
          implicitHeight: visible ? historyView.implicitHeight : 0
          focus: root.historyOpen

          Keys.onPressed: function (event) {
            var ctrlMod = (event.modifiers & Qt.ControlModifier) !== 0
            var shiftMod = (event.modifiers & Qt.ShiftModifier) !== 0

            if (event.key === Qt.Key_Escape || (ctrlMod && event.key === Qt.Key_H)) {
              root.toggleHistory()
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K
                       || (ctrlMod && event.key === Qt.Key_P)) {
              historyView.move(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J
                       || (ctrlMod && event.key === Qt.Key_N)) {
              historyView.move(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (shiftMod) historyView.resume()
              else historyView.activate()
              event.accepted = true
            }
          }

          HistoryView {
            id: historyView
            width: parent.width
            turns: history.turns
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChosen: function (turnIndex) {
              root.showTurn(turnIndex)
              root.historyOpen = false
              Qt.callLater(function () { root.focusActiveSurface() })
            }
            onResumeInTerminal: function (turnIndex) { root.resumeTurnInTerminal(turnIndex) }
          }
        }

        // ---------------------------------------------------------- picker
        Item {
          id: pickerKeys
          width: parent.width
          visible: root.pickerOpen
          implicitHeight: visible ? filePicker.implicitHeight : 0
          focus: root.pickerOpen

          Keys.onPressed: function (event) {
            var ctrlMod = (event.modifiers & Qt.ControlModifier) !== 0

            if (event.key === Qt.Key_Escape) {
              root.togglePicker()
              event.accepted = true
            } else if (ctrlMod && event.key === Qt.Key_H) {
              filePicker.toggleHidden()
              event.accepted = true
            } else if (event.key === Qt.Key_Up || (ctrlMod && event.key === Qt.Key_P)) {
              filePicker.move(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down || (ctrlMod && event.key === Qt.Key_N)) {
              filePicker.move(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              filePicker.activate()
              event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
              filePicker.back()
              event.accepted = true
            } else if (event.key === Qt.Key_Left) {
              filePicker.up()
              event.accepted = true
            } else if (event.text && event.text.length === 1
                       && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              // Typing filters. There is no separate search box to focus,
              // which is the whole point of a list you drive with the keyboard.
              filePicker.setFilter(filePicker.filter + event.text)
              event.accepted = true
            }
          }

          FilePicker {
            id: filePicker
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            onAttached: function (path) {
              root.addAttachment("file", path)
              root.togglePicker()
            }
            onCancelled: root.togglePicker()
          }
        }

        // -------------------------------------------------------- settings
        Item {
          id: settingsKeys
          width: parent.width
          visible: root.settingsOpen
          implicitHeight: visible ? settingsView.implicitHeight : 0
          focus: root.settingsOpen

          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Comma)) {
              root.toggleSettings()
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
              settingsView.move(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
              settingsView.move(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                       || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
              settingsView.activate()
              event.accepted = true
            }
          }

          SettingsView {
            id: settingsView
            width: parent.width
            config: config
            agent: root.agent
            installedAgents: root.installedAgents
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        // ----------------------------------------------------------- input
        BorderSurface {
          visible: !root.settingsOpen && !root.pickerOpen && !root.historyOpen
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
            placeholderText: "Ask " + (root.effectiveAgent || "an agent") + "…"
            color: root.foreground
            placeholderTextColor: Qt.darker(root.foreground, 1.6)
            selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            background: null

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function (event) {
              var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              var shift = (event.modifiers & Qt.ShiftModifier) !== 0

              if (event.key === Qt.Key_Escape) {
                // Closing never cancels. The agent keeps writing, the answer
                // is recorded, and a notification brings you back to it —
                // losing a paid-for answer to a reflex keypress is the whole
                // problem this is meant to remove. Ctrl+C actually stops one.
                root.dismiss()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_T && root.thinking) {
                root.thinkingOpen = !root.thinkingOpen
                event.accepted = true
              } else if (ctrl && shift && event.key === Qt.Key_C) {
                // Ctrl+Shift+C is copy in every terminal on this desktop, and
                // it leaves plain Ctrl+C free to stop a run.
                root.copyAnswer()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_C && root.runState === "running"
                         && !input.selectedText) {
                // Only with no selection: Ctrl+C has to stay "copy" whenever
                // there is something selected to copy.
                root.cancelRun()
                event.accepted = true
              } else if (event.key === Qt.Key_Up && root.cursorOnFirstLine()) {
                if (root.recallPrompt(1)) event.accepted = true
              } else if (event.key === Qt.Key_Down && root.historyIndex >= 0 && root.cursorOnLastLine()) {
                if (root.recallPrompt(-1)) event.accepted = true
              } else if (ctrl && shift && event.key === Qt.Key_A) {
                // Shift is not optional: plain Ctrl+A has to stay select-all in
                // a text box.
                root.cycleAgent(1)
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_H) {
                root.toggleHistory()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_O) {
                root.togglePicker()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_Comma) {
                root.toggleSettings()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_S) {
                root.captureWindow()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_R) {
                root.captureRegion()
                event.accepted = true
              } else if (ctrl && shift && event.key === Qt.Key_V) {
                // Ctrl+Shift+V attaches; plain Ctrl+V stays paste-into-the-field,
                // which is what a text box is expected to do.
                root.attachClipboard()
                event.accepted = true
              } else if (ctrl && shift && event.key === Qt.Key_Backspace && root.attachments.length) {
                // Shift is not optional here: plain Ctrl+Backspace has to stay
                // "delete the previous word", which a composer needs far more
                // often than it needs to drop an attachment.
                root.removeAttachment(root.attachments.length - 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Ctrl+Enter inserts a newline; bare Enter and Shift+Enter
                // both send, so the send path is never a surprise.
                if (ctrl) input.insert(input.cursorPosition, "\n")
                else if (shift) root.submitToTerminal()
                else if (config.get("sendMode") === "terminal") root.submitToTerminal()
                else root.submitInline()
                event.accepted = true
              }
            }
          }
        }

        // ------------------------------------------------------ context row
        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          visible: chipRepeater.count > 0 && !root.settingsOpen && !root.pickerOpen && !root.historyOpen

          Repeater {
            id: chipRepeater
            model: {
              var chips = []
              if (root.ctxClass)
                chips.push({ glyph: "", label: root.ctxClass, index: -1 })
              if (root.ctxCwd)
                chips.push({ glyph: "", label: root.prettyPath(root.ctxCwd), index: -1 })

              // Attachments carry an index so their chip can remove them.
              // Automatic context has index -1: it says where the question came
              // from, and is not the user's to curate.
              for (var i = 0; i < root.attachments.length; i++) {
                var a = root.attachments[i]
                chips.push({ glyph: a.kind === "clipboard" ? "\uf0ea" : "\uf03e",
                             label: a.label, index: i })
              }
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

                // Only attachments get a remove affordance. Automatic context
                // is a description of where the question came from, not a list
                // the user is meant to prune.
                Text {
                  visible: chip.modelData.index >= 0
                  text: "\u00d7"
                  color: root.foreground
                  opacity: removeArea.containsMouse ? 1 : 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter

                  MouseArea {
                    id: removeArea
                    anchors.fill: parent
                    anchors.margins: -Style.spacing.xs
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removeAttachment(chip.modelData.index)
                  }
                }
              }
            }
          }
        }

        // ---------------------------------------------------------- footer
        Text {
          width: parent.width
          visible: root.notice !== ""
          text: root.notice
          color: Color.accent
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.foreground
          opacity: 0.12
        }

        // ---------------------------------------------------------- answer
        Item {
          width: parent.width
          visible: root.runState !== "idle" && !root.settingsOpen && !root.pickerOpen && !root.historyOpen
          implicitHeight: visible
            ? Math.max(Style.space(20), Math.min(answerColumn.implicitHeight, root.maxAnswerHeight))
            : 0

          Flickable {
            id: answerFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: answerColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Follow the tail while the answer is being written, but stop
            // fighting the user the moment the turn is over and they scroll
            // back up to read.
            onContentHeightChanged: {
              if (root.runState === "running")
                contentY = Math.max(0, contentHeight - height)
            }

            Column {
              id: answerColumn
              width: answerFlick.width
              spacing: Style.spacing.xs

              // The asked question, with the copy affordance parked on its
              // right. Putting it here rather than floating over the answer
              // keeps it from ever sitting on top of the text it copies.
              Item {
                width: parent.width
                visible: root.askedPrompt !== ""
                implicitHeight: Math.max(askedText.implicitHeight, copyButton.implicitHeight)
                          + Style.spacing.xxs

                Text {
                  id: askedText
                  anchors.left: parent.left
                  anchors.right: copyButton.visible ? copyButton.left : parent.right
                  anchors.rightMargin: copyButton.visible ? Style.spacing.sm : 0
                  anchors.top: parent.top
                  text: root.askedPrompt
                  color: root.foreground
                  opacity: 0.5
                  wrapMode: Text.Wrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  id: copyButton
                  anchors.right: parent.right
                  anchors.top: parent.top
                  visible: root.answer !== "" && root.runState !== "running"
                  implicitWidth: copyLabel.implicitWidth + Style.spacing.sm * 2
                  implicitHeight: copyLabel.implicitHeight + Style.spacing.xxs * 2
                  radius: Math.max(Style.space(2), Style.cornerRadius)
                  color: copyArea.containsMouse ? Style.hoverFill : Style.normalFill
                  border.width: Style.normalBorderWidth
                  border.color: copyArea.containsMouse ? Style.hoverBorderColor : Style.normalBorderColor

                  Text {
                    id: copyLabel
                    anchors.centerIn: parent
                    text: "copy"
                    color: root.foreground
                    opacity: copyArea.containsMouse ? 0.95 : 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: copyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyAnswer()
                  }
                }
              }

              // Status doubles as the disclosure for the reasoning. Folded by
              // default: the answer is what was asked for, and reasoning that
              // pushes it off screen is a cost, not a feature.
              Item {
                width: parent.width
                visible: root.status !== "" || root.thinking !== ""
                implicitHeight: statusRow.implicitHeight

                Row {
                  id: statusRow
                  spacing: Style.spacing.xs

                  Text {
                    text: root.thinking
                          ? (root.thinkingOpen ? "\uf078" : "\uf054")
                          : ""
                    color: Color.accent
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: {
                      if (root.status === "thinking") return "thinking…"
                      if (root.status) return root.status + "…"
                      return root.thinkingOpen ? "reasoning" : "reasoning available"
                    }
                    color: Color.accent
                    opacity: 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: root.thinking !== ""
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.thinkingOpen = !root.thinkingOpen
                }
              }

              // The reasoning itself, offset and dimmed so it never reads as
              // the answer.
              Text {
                width: parent.width
                visible: root.thinkingOpen && root.thinking !== ""
                text: root.thinking
                color: root.foreground
                opacity: 0.45
                wrapMode: Text.Wrap
                leftPadding: Style.spacing.md
                bottomPadding: Style.spacing.xs
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                width: parent.width
                visible: root.answer !== ""
                spacing: Style.spacing.sm

                // A quoted-passage rule rather than a box: it marks the answer
                // as the agent's voice without drawing another rectangle.
                Rectangle {
                  width: Math.max(1, Style.space(2))
                  height: answerText.implicitHeight
                  color: root.runState === "error" ? Color.urgent : Color.accent
                  opacity: 0.55
                }

                Item {
                  width: parent.width - parent.spacing - Style.space(2)
                  implicitHeight: answerText.implicitHeight

                  // TextEdit, not Text: it can say where the last character
                  // actually is (positionToRectangle), which is what puts the
                  // stream cursor in the right place instead of guessing from
                  // contentWidth. Read-only, and selectable so an answer can
                  // be copied out — clicking into it takes focus, click back
                  // in the box to keep typing.
                  TextEdit {
                    id: answerText
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    text: root.answer
                // MarkdownText is why the agent's lists, code spans and
                // emphasis land as formatting instead of as literal asterisks.
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                    color: root.runState === "error" ? Color.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    onLinkActivated: function (link) { Quickshell.execDetached(["xdg-open", link]) }
                  }

                  // Sits at the end of the last line while text is arriving.
                  // A terminal's own idiom, on a desktop that is mostly
                  // terminals.
                  Rectangle {
                    id: streamCursor
                    visible: root.runState === "running"

                    // Recomputed on every delta: touching answerText.text is
                    // what makes this binding depend on it.
                    readonly property rect tail: {
                      answerText.text
                      return answerText.positionToRectangle(answerText.length)
                    }

                    width: Style.space(7)
                    height: Math.max(Style.space(4), tail.height)
                    color: Color.accent
                    x: Math.min(tail.x, answerText.width - width)
                    y: tail.y

                    SequentialAnimation on opacity {
                      running: root.runState === "running" && root.animate
                      loops: Animation.Infinite
                      NumberAnimation { to: 0.15; duration: 420 }
                      NumberAnimation { to: 0.9; duration: 420 }
                    }
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          visible: root.runState !== "idle" && !root.settingsOpen && !root.pickerOpen && !root.historyOpen
          height: Style.spacing.hairline
          color: root.foreground
          opacity: 0.12
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm

          Repeater {
            // The hint row states what the keys do *now*. A static legend
            // that still offers "send" while a run is in flight teaches the
            // wrong thing.
            model: {
              if (root.historyOpen)
                return [{ keys: ["enter"], label: "reopen" },
                        { keys: ["shift", "enter"], label: "resume in terminal" },
                        { keys: ["esc"], label: "back" }]
              if (root.pickerOpen)
                return [{ keys: ["enter"], label: "open" },
                        { keys: ["bksp"], label: "up" },
                        { keys: ["ctrl", "h"], label: "hidden" },
                        { keys: ["esc"], label: "back" }]
              if (root.settingsOpen)
                return [{ keys: ["space"], label: "change" },
                        { keys: ["esc"], label: "back" }]
              if (root.runState === "running")
                return [{ keys: ["esc"], label: "close, keeps running" },
                        { keys: ["ctrl", "c"], label: "stop" }]

              var hints = [{
                keys: ["enter"],
                label: root.runState === "idle"
                  ? (root.inlineAvailable ? "send" : "send to terminal")
                  : "follow up"
              }]
              hints.push({ keys: ["shift", "enter"], label: "terminal" })
              if (root.answer) hints.push({ keys: ["ctrl", "shift", "c"], label: "copy" })
              if (root.thinking) hints.push({ keys: ["ctrl", "t"], label: "reasoning" })
              if (root.runState === "idle") {
                hints.push({ keys: ["ctrl", "s"], label: "window" })
                hints.push({ keys: ["ctrl", "r"], label: "region" })
                hints.push({ keys: ["ctrl", "shift", "v"], label: "clip" })
                hints.push({ keys: ["ctrl", "o"], label: "file" })
                hints.push({ keys: ["ctrl", "h"], label: "history" })
              }
              if (root.canSwitchAgent)
                hints.push({ keys: ["ctrl", "shift", "a"], label: "agent" })
              hints.push({ keys: ["ctrl", ","], label: "settings" })
              hints.push({ keys: ["esc"], label: "close" })
              return hints
            }

            // Each key and its action share one outline, so the eye groups
            // "ctrl+shift+v" with "clip" instead of guessing where one hint
            // ends and the next begins. The group's border is deliberately
            // fainter than the key caps' — nesting two equal outlines reads
            // as noise.
            delegate: Rectangle {
              id: hint
              required property var modelData

              implicitWidth: hintRow.implicitWidth + Style.spacing.sm * 2
              implicitHeight: hintRow.implicitHeight + Style.spacing.xs * 2
              radius: Math.max(Style.space(3), Style.cornerRadius)
              color: "transparent"
              border.width: Math.max(1, Style.normalBorderWidth)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

              // RowLayout rather than Row: a key cap is taller than its
              // caption, and only a layout can center the two against each
              // other. Row would top-align them and the captions would ride
              // high.
              RowLayout {
                id: hintRow
                anchors.centerIn: parent
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
                  opacity: 0.55
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
}
