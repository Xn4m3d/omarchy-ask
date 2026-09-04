.pragma library

// Adapters that turn "ask this agent a question" into an argv, and the agent's
// NDJSON stdout into a handful of events the overlay can render.
//
// An adapter is two pure functions:
//
//   argv(opts)   -> [command, ...args]
//   parse(line)  -> { kind, ... } | null
//
// kind is one of:
//   "session"  { sessionId }   the id to pass back for a follow-up turn
//   "delta"    { text }        text to append to the answer
//   "thinking" { text }        reasoning, rendered dimmed and discarded on turn end
//   "tool"     { text }        a tool the agent reached for, shown as status
//   "done"     { text }        the turn finished; text is the final answer if we
//                              never saw deltas
//   "error"    { text }        the agent reported a failure
//
// Anything unrecognised returns null, which the runner ignores. That is the
// point: these formats gain event types over time, and an unknown line must
// never be fatal.

// Read-only by default. This is a global hotkey that can be hit from anywhere,
// so the inline path gets tools that observe and none that change anything;
// escalation to a real terminal is one Shift+Enter away, where approvals are
// visible.
var READ_ONLY_TOOLS = "Read Grep Glob WebFetch WebSearch"

// Claude Code and Grok share an envelope: system/init carries the session id,
// deltas arrive as Anthropic stream_event content_block_delta, and a final
// result object closes the turn. Verified against Claude Code; Grok documents
// `streaming-messages-json` as the same Messages wire format.
function parseAnthropicEnvelope(line) {
  var m
  try {
    m = JSON.parse(line)
  } catch (e) {
    return null
  }
  if (!m || typeof m !== "object") return null

  if (m.type === "system" && m.subtype === "init" && m.session_id)
    return { kind: "session", sessionId: String(m.session_id) }

  if (m.type === "stream_event" && m.event) {
    var ev = m.event

    if (ev.type === "content_block_delta" && ev.delta) {
      if (ev.delta.type === "text_delta" && ev.delta.text)
        return { kind: "delta", text: String(ev.delta.text) }
      if (ev.delta.type === "thinking_delta" && ev.delta.thinking)
        return { kind: "thinking", text: String(ev.delta.thinking) }
      return null
    }

    if (ev.type === "content_block_start" && ev.content_block
        && ev.content_block.type === "tool_use")
      return { kind: "tool", text: String(ev.content_block.name || "tool") }

    return null
  }

  if (m.type === "result") {
    if (m.is_error)
      return { kind: "error", text: String(m.result || m.subtype || "the agent reported an error") }
    return {
      kind: "done",
      text: String(m.result || ""),
      sessionId: m.session_id ? String(m.session_id) : ""
    }
  }

  return null
}

var claude = {
  id: "claude",
  argv: function (opts) {
    var a = ["claude", "-p", opts.prompt,
             "--output-format", "stream-json",
             "--verbose",
             "--include-partial-messages",
             // Without this, a permission prompt in --print mode has nobody to
             // answer it and the run hangs instead of declining.
             "--permission-prompts", "none"]
    if (opts.allowedTools) a.push("--allowed-tools", opts.allowedTools)
    if (opts.sessionId) a.push("--resume", opts.sessionId)
    return a
  },
  parse: parseAnthropicEnvelope
}

var grok = {
  id: "grok",
  argv: function (opts) {
    var a = ["grok", "-p", opts.prompt,
             "--output-format", "streaming-messages-json",
             "--include-partial-messages"]
    if (opts.cwd) a.push("--cwd", opts.cwd)
    if (opts.sessionId) a.push("--resume", opts.sessionId)
    return a
  },
  parse: parseAnthropicEnvelope
}

// Every other agent omarchy-agent knows about routes to a terminal instead of
// streaming here. That is a deliberate floor rather than a gap: a wrong guess
// at an output format produces a card that sits there empty, while the
// terminal path already works for all of them.
var ADAPTERS = { claude: claude, grok: grok }

function forAgent(name) {
  return ADAPTERS[String(name)] || null
}

function supportsInline(name) {
  return forAgent(name) !== null
}
