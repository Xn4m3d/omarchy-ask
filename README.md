# ask

A composer for your default coding agent, summoned from anywhere with
`SUPER+Q`.

Omarchy already knows how to hand an agent a pre-filled prompt — that is what
the "Process crashed:" notification does through `omarchy-agent-crash`. This
generalizes it: one keypress opens a card, you type a question, and it goes to
whichever agent `omarchy default agent` points at, along with the context of
what you were actually looking at.

```
┌──────────────────────────────────────────┐
│ ● ask                             claude │
│ ┌──────────────────────────────────────┐ │
│ │ pourquoi mon build casse ?           │ │
│ └──────────────────────────────────────┘ │
│  foot    ~/Projects/thing              │
│ ──────────────────────────────────────── │
│ enter send   ctrl enter newline  esc close│
└──────────────────────────────────────────┘
```

## Install

```bash
omarchy plugin add https://github.com/Xn4m3d/omarchy-ask.git --enable --yes
```

Then bind it. In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + Q", "Ask agent", "omarchy-ask")
```

`bin/omarchy-ask` has to be on `PATH` — symlink it into `~/.local/bin`:

```bash
ln -sf ~/.config/omarchy/plugins/xn4m3d.ask/bin/omarchy-ask ~/.local/bin/omarchy-ask
```

## How it works

The overlay lives inside the already-running `omarchy-shell` Quickshell
process, so summoning it is an IPC call into something warm rather than a cold
start.

```
SUPER+Q → omarchy-ask → omarchy-shell shell toggle xn4m3d.ask '<payload>'
                                             └→ Ask.qml open(payload)
```

**Context is collected by the wrapper, before the IPC call.** This is the one
structural constraint: as soon as the layer-shell card takes keyboard focus,
`hyprctl activewindow` no longer describes what the user was looking at. So
`bin/omarchy-ask` gathers the facts first and passes them along as JSON.

What it collects today:

| Fact | How |
|---|---|
| Window class, title, address | `hyprctl activewindow -j` |
| Working directory | first direct child of the window pid, then `/proc/<pid>/cwd` |

The cwd trick is what makes a question actionable: for a terminal, the window's
pid is the terminal, and its first child is the shell whose cwd you care about.
Walking the tree to its deepest leaf looks more thorough but lands on
short-lived processes whose `/proc` entry is often already gone.

The screensaver and lock surfaces are filtered out — they are what the
compositor reports while they are up, but the window underneath is what you
meant, and it is no longer reachable. No window context beats confidently wrong
context.

## Keys

| Key | Does |
|---|---|
| `enter` | send — streams the answer in the card |
| `shift+enter` | send to a terminal agent instead |
| `ctrl+enter` | newline |
| `ctrl+s` | attach a shot of the window you came from |
| `ctrl+r` | attach a screen region (Omarchy's frozen-screen picker) |
| `ctrl+shift+v` | attach the clipboard (image or text) |
| `ctrl+shift+backspace` | drop the last attachment |
| `ctrl+,` | settings |
| `esc` | stop a running answer, then close |

Attachments show up as chips and travel to the agent **as file paths**: every
agent can already read a file it is pointed at, so nothing here needs a
per-agent upload protocol.

Nothing is attached without a keystroke. A clipboard that shipped with every
question would eventually ship a password.

## Sending

`enter` composes the prompt (your text plus a short context block, shaped like
the one `omarchy-agent-crash` builds) and hands it to `omarchy-agent --prompt`,
which routes it to your default agent in a terminal tagged
`org.omarchy.agent`.

When a working directory was captured, the agent is started **in** it:
`omarchy-agent` redirects to `~/Work` when it starts from `$HOME`, so the
directory has to be applied before it runs.

`enter` streams the answer into the card. `shift+enter` sends the same
question to a terminal instead, which is also where anything that needs to
*change* something belongs: the inline path runs read-only
(`--permission-prompts none` plus a tools allowlist), because a global hotkey
that can auto-approve writes from anywhere is not a trade worth making.

Agents whose streaming format has an adapter answer inline; the rest fall back
to the terminal rather than showing a card that never fills in.

| Agent | Inline | Note |
|---|---|---|
| `claude` | yes | verified against Claude Code's `stream-json` |
| `grok` | yes | same Anthropic envelope; **not yet verified** — no signed-in CLI here |
| everything else | no | terminal, via `omarchy-agent` |

## Settings

`ctrl+,` opens the settings screen. Space changes the selected value; booleans
flip, enums advance.

| Setting | Default | What it does |
|---|---|---|
| `captureWindow` | `true` | attach class and title of the window you came from |
| `captureCwd` | `true` | resolve the terminal's directory and run the agent in it |
| `sendMode` | `inline` | what plain `enter` does |
| `agent` | `""` | force an agent for the inline path; empty follows `omarchy default agent` |
| `inlineTools` | `Read Grep Glob WebFetch WebSearch` | tools the inline run may use |

They live in `~/.config/omarchy/ask.json`, deliberately outside this checkout:
`omarchy plugin update` fast-forwards the plugin directory and would walk over
a config file kept inside it. Only changed keys are written.

## Theming

Every color and dimension comes from the shell's `qs.Commons` singletons —
`Color.menu.*` for the surface, `Style.*` for spacing and type. There is not a
single literal color in the QML, so the card follows whatever theme is active
without any per-theme work.

## Hacking on it

A plugin is a plain git checkout in `~/.config/omarchy/plugins/<id>/`, so clone
it there and edit in place.

Saving a file under that directory triggers a plugin reload, but **an overlay
with `keepLoaded: true` keeps its mounted instance**, so UI edits do not always
appear. When a change seems not to apply:

```bash
omarchy restart shell
```

Third-party plugins run unsandboxed inside `omarchy-shell`. If a change breaks
the shell, the way back is:

```bash
omarchy plugin disable xn4m3d.ask && omarchy restart shell
```

Useful while iterating:

```bash
# see the context without opening anything
omarchy-ask --print-context

# drive the overlay by hand, with a made-up context
omarchy-shell shell summon xn4m3d.ask '{"window":{"class":"foot","title":"x"},"cwd":"/tmp"}'
omarchy-shell shell hide xn4m3d.ask

# QML warnings land in the journal
journalctl --user _PID=$(pgrep -f 'quickshell -n -p /usr/share/omarchy/shell') -f
```

## Not there yet

- **A file picker.** `ctrl+o` is unclaimed. For now, typing a path into the
  question works — the agent reads it like any other path.
- **Grok inline is unverified.** The format matches Claude's on paper and the
  adapter is written, but nothing here is signed in to xAI to prove it.
- **Codex has no adapter.** `codex exec --json` speaks its own event format;
  until someone writes that adapter, codex answers in a terminal.

## License

MIT
