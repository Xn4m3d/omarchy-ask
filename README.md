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
| `ctrl+o` | attach a file — opens the picker |
| `↑` `↓` | recall previous prompts (from the first/last line of the box) |
| `ctrl+h` | history — past turns, reopenable and resumable |
| `ctrl+c` | stop a running answer |
| `ctrl+shift+backspace` | drop the last attachment |
| `ctrl+,` | settings |
| `esc` | close — the agent keeps running |

Attachments show up as chips and travel to the agent **as file paths**: every
agent can already read a file it is pointed at, so nothing here needs a
per-agent upload protocol.

Nothing is attached without a keystroke. A clipboard that shipped with every
question would eventually ship a password.

## Sending

Either way, the prompt is your text plus a short context block, shaped like the
one `omarchy-agent-crash` builds — plain facts under a heading, which every
agent reads without special handling.

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

The terminal path goes through `omarchy-agent --prompt`, which opens a window
tagged `org.omarchy.agent`. When a working directory was captured, the agent
starts **in** it: `omarchy-agent` redirects to `~/Work` when it starts from
`$HOME`, so the directory has to be applied before it runs.

## Nothing is lost when you close

Closing the card **never cancels the agent**. The turn keeps running, the
answer is recorded, and when it lands on a closed card a notification says so —
clicking it reopens the card on that answer (`omarchy-ask --last`).

That is the whole point of `esc` not being a cancel key: losing an answer you
already paid for, to a reflex keypress, is exactly the failure this is meant to
remove. `ctrl+c` stops a run when you actually mean to.

Every turn is recorded in `~/.local/state/omarchy/ask/history.json` — prompt,
answer, agent, directory, and the agent's **session id** — capped at the last
50. Delete the file to clear it.

## History

`↑` recalls previous prompts the way a shell does, but only from the first line
of the box: below that, `↑` has to stay "move the cursor up" or a multi-line
question becomes uneditable. Whatever you were typing is handed back when you
walk `↓` out of history.

`ctrl+h` opens the full history: past turns, newest first.

| Key | Does |
|---|---|
| `enter` | reopen the turn — answer restored, session id restored, so Enter continues it |
| `shift+enter` | resume that session in a terminal (`claude --resume <id>`) |
| `esc` | back |

The session id is what makes this a continuation rather than a re-ask. A turn
that has none — cancelled early, or run by an agent without adapter support —
falls back to re-sending the prompt rather than issuing a broken resume.

## The file picker

`ctrl+o` opens a keyboard-driven picker, starting in the directory the question
came from — attaching a file from the project you were just looking at is the
common case by a wide margin.

| Key | Does |
|---|---|
| type | filter the listing |
| `↑` `↓` (or `ctrl+p` / `ctrl+n`) | move |
| `enter` | enter a directory, or attach a file |
| `backspace` | trim the filter, or go up when it is empty |
| `←` | go up |
| `ctrl+h` | show hidden entries |
| `esc` | back to the composer |

It is built in rather than shelling out to a portal dialog: the card already
owns keyboard focus, and handing that to a GTK file chooser would mean a second
window, a second focus dance, and a theme that does not match.

Listing goes through `bin/omarchy-ask-ls`, which uses `find -printf` rather
than `ls -1`: a filename containing a newline makes `ls` output unparseable,
and unparseable here means attaching the wrong file. Symlinks are classified by
what they point at (`-xtype`), so a link to a directory is enterable and a link
to a file is attachable.

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

- **Grok inline is unverified.** The format matches Claude's on paper and the
  adapter is written, but nothing here is signed in to xAI to prove it.
- **Codex has no adapter.** `codex exec --json` speaks its own event format;
  until someone writes that adapter, codex answers in a terminal.

## License

MIT
