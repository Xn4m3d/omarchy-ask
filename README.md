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

## Sending

`enter` composes the prompt (your text plus a short context block, shaped like
the one `omarchy-agent-crash` builds) and hands it to `omarchy-agent --prompt`,
which routes it to your default agent in a terminal tagged
`org.omarchy.agent`.

When a working directory was captured, the agent is started **in** it:
`omarchy-agent` redirects to `~/Work` when it starts from `$HOME`, so the
directory has to be applied before it runs.

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

## License

MIT
