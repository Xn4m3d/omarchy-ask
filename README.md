# ask

**Ask your coding agent anything, from anywhere, without losing what you were doing.**

`SUPER+Q` opens a card over whatever is on screen. Type a question. It goes to
your default Omarchy agent — with the window you were looking at, the directory
you were in, and anything you chose to attach — and the answer streams back in
place.

```
┌────────────────────────────────────────────────────────────┐
│ ● ask                                       claude · opus-5│
│                                        5h 83% · 7d 9% · Pro│
│  ┌───────────────────────────────────────────────────────┐ │
│  │ why is this build failing?                            │ │
│  └───────────────────────────────────────────────────────┘ │
│  [win] foot   [dir] ~/Projects/api   [img] region shot ×   │
│ ────────────────────────────────────────────────────────── │
│  why is this build failing?                        ┌──────┐│
│                                                    │ copy ││
│ ▎Your lockfile is out of sync with package.json.   └──────┘│
│ ▎Run `bun install` to regenerate it — the CI image         │
│ ▎pins bun 1.1, the lockfile was written by 1.2.▋           │
│ ────────────────────────────────────────────────────────── │
│ [enter] follow up  [shift][enter] terminal  [esc] close    │
└────────────────────────────────────────────────────────────┘
```

<!-- Screenshots and short screen recordings live in docs/ and get linked here. -->

---

## Install

```bash
omarchy plugin add https://github.com/Xn4m3d/omarchy-ask.git --enable --yes
ln -sf ~/.config/omarchy/plugins/xn4m3d.ask/bin/omarchy-ask ~/.local/bin/omarchy-ask
```

Then one line in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + Q", "Ask agent", "omarchy-ask")
```

That is the whole installation. **No package to install, no service to enable,
no API key to paste.**

## Why there is nothing to set up

On Omarchy every moving part this needs is already running. `ask` is glue, not
a stack:

| What it needs | Already on your machine |
|---|---|
| A QML host that is already warm | `quickshell` — a direct dependency of `omarchy` |
| Routing a prompt to *your* agent | `omarchy-agent`, `omarchy default agent` |
| A frozen-screen region picker | `omarchy-capture-region` — the same UX as `SUPER+SHIFT+S` |
| Screenshots and clipboard | `grim`, `slurp`, `wl-clipboard` — all in `omarchy-base.packages` |
| Rate-limit numbers | `omarchy-agent-usage-update`, whose records the bar widget already draws |
| Desktop notifications | `omarchy-notification-send` |
| JSON on the shell side | `jq` — a direct dependency of `omarchy` |
| Theme, spacing, type | the shell's own `qs.Commons` singletons |
| Install and update | `omarchy plugin add` / `update` |

What `ask` adds is **~2,700 lines of QML and three bash helpers**. It never
talks to a model API itself — it drives the agent CLI you already signed in to.

Because it leans on `omarchy-agent`, it works with **every agent Omarchy
supports** (claude, codex, grok, gemini, copilot, opencode, crush, pi).
Streaming the answer *inside the card* needs a per-agent adapter; everything
else falls back to a terminal, which is generic by construction — see
[Agent support](#agent-support).

## What it does

**It brings the context with it.** The class and title of the window you came
from, and — for a terminal — the working directory, resolved from the shell
running inside it. The agent starts *in* that directory, so "why is this
failing?" is a question about your project rather than about nothing.

**It attaches what you point at.** `ctrl+s` shoots the window you came from,
`ctrl+r` picks a screen region through Omarchy's own frozen-screen picker,
`ctrl+shift+v` takes the clipboard (image or text), `ctrl+o` opens a
keyboard-driven file picker. Each becomes a removable chip and travels to the
agent **as a file path** — so it works identically for every agent, with no
upload protocol anywhere.

Nothing is attached without a keystroke. A clipboard that shipped with every
question would eventually ship a password.

**It answers in place, or hands off.** `enter` streams the answer into the card
as rendered markdown. `shift+enter` sends the same question to a real agent
terminal instead. The inline path is **read-only** — a global hotkey that can
auto-approve writes from anywhere is not a trade worth making — so anything that
changes files belongs in the terminal, where approvals are in front of you.

**It never loses an answer.** Closing the card does not cancel the agent. The
turn keeps running, the answer is recorded, and a notification brings you back
to it. `ctrl+c` stops a run when that is what you actually mean.

**It remembers.** `↑` recalls previous prompts, shell-style. `ctrl+h` opens
every past turn — each carrying the agent's **session id**, so reopening one
continues that conversation instead of re-asking it, and `shift+enter` resumes
it in a terminal through the agent's own `--resume`.

**It says what it is doing.** Which model answered, how much of your rate limit
is gone, and — folded away until you want it — the agent's reasoning.

## Keys

| Key | Does |
|---|---|
| `SUPER+Q` | open / close |
| `enter` | send — streams the answer here (or follow up, once there is one) |
| `shift+enter` | send to a terminal agent instead |
| `ctrl+enter` | newline |
| `↑` `↓` | recall previous prompts, from the first/last line of the box |
| `ctrl+s` | attach a shot of the window you came from |
| `ctrl+r` | attach a screen region |
| `ctrl+shift+v` | attach the clipboard (image or text) |
| `ctrl+o` | attach a file — opens the picker |
| `ctrl+shift+backspace` | drop the last attachment |
| `ctrl+shift+c` | copy the answer (a `copy` button sits beside the question too) |
| `ctrl+t` | fold the agent's reasoning open or shut |
| `ctrl+h` | history |
| `ctrl+,` | settings |
| `ctrl+c` | stop a running answer |
| `esc` | close — the agent keeps running |

## Agent support

| Agent | Inline streaming | Notes |
|---|---|---|
| `claude` | yes | verified end to end against Claude Code's `stream-json` |
| `grok` | adapter written, **unverified** | same Anthropic envelope on paper; no signed-in CLI here to prove it |
| everything else | no — terminal | via `omarchy-agent --prompt`, which works for all of them |

Adding an agent is two pure functions in [`agents.js`](agents.js): `argv(opts)`
and `parse(line)`. An unrecognised line returns `null` and is ignored — these
formats gain event types over time, and an unknown line must never be fatal.

## Settings — `ctrl+,`

Space changes the selected value; booleans flip, enums advance.

| Setting | Default | What it does |
|---|---|---|
| `captureWindow` | `true` | attach class and title of the window you came from |
| `captureCwd` | `true` | resolve the terminal's directory and run the agent in it |
| `sendMode` | `inline` | what plain `enter` does |
| `agent` | `""` | force an agent for the inline path; empty follows `omarchy default agent` |
| `reasoningTokens` | `0` | thinking budget for the inline run; `0` disables it |
| `animations` | `true` | entrance, activity pulse, streaming cursor |
| `inlineTools` | `Read Grep Glob WebFetch WebSearch` | tools the inline run may use |

They live in `~/.config/omarchy/ask.json`, deliberately **outside** this
checkout: `omarchy plugin update` fast-forwards the plugin directory and would
walk over a config file kept inside it. Only changed keys are written.

## Tested, and not

Built and exercised on a single machine. Being straight about which is which:

**Verified by running it**

- Summon → type → send → answer, on Claude, repeatedly.
- The agent really starts in the captured directory (checked through `/proc/<pid>/cwd`).
- Attachments: window shot, region, clipboard text, file picker — files land,
  chips appear, paths reach the prompt.
- A window screenshot contains the window and **not** the ask card. This took a
  fix: `grim` fired before the compositor had dropped our surface, and baked a
  ghost of the card into the image.
- Closing mid-run leaves the agent running and the answer recorded.
- Follow-ups reuse the session id — the answer stays on topic when the question
  no longer names the topic.
- `ctrl+shift+c` really puts the answer on the clipboard.
- Live theme switching restyles the open card (Solitude → Catppuccin → Gruvbox).
- Empty history, empty directory, unreadable directory, and filenames with
  spaces, accents and apostrophes.
- Prompt quoting against `$VAR`, backticks, `$(…)` and apostrophes.
- The adapter parser, unit-tested on real lines including malformed JSON.

**Written but not observed**

- **Grok inline.** No signed-in xAI CLI on this machine, so the adapter has
  never actually run.
- **The `copy` button's click.** The shortcut is verified and the button calls
  the same function, but there is no synthetic-mouse tool here — no click has
  ever been sent to this card. It is the only untested *click* in the whole UI.
- **The reasoning panel, end to end.** The parser is unit-tested, and
  `MAX_THINKING_TOKENS` does produce `thinking_delta` from the CLI, but every
  run through the UI answered without a reasoning block — so the rendered panel
  has not been seen.

**Out of scope for now**

- Non-Hyprland compositors: context collection is `hyprctl`, by design.
- Multi-monitor, and scale factors other than the one it was built on.
- Codex: `codex exec --json` speaks its own event format and has no adapter yet.

## How it works

The overlay lives inside the already-running `omarchy-shell` Quickshell process,
so summoning it is an IPC call into something warm rather than a cold start.

```
SUPER+Q → omarchy-ask → omarchy-shell shell toggle xn4m3d.ask '<payload>'
                                            └→ Ask.qml open(payload)
```

**Context is collected by the wrapper, before the IPC call.** That is the one
structural constraint: as soon as the layer-shell card takes keyboard focus,
`hyprctl activewindow` no longer describes what you were looking at. So
`bin/omarchy-ask` gathers the facts first and hands them over as JSON — which
also makes the whole thing drivable from a shell, with no keyboard involved.

A few decisions worth knowing about:

- **The cwd comes from the window pid's first child**, not from walking the
  process tree to its deepest leaf: that lands on short-lived processes whose
  `/proc` entry is often already gone.
- **Listing uses `find -printf`, not `ls -1`** — a filename containing a newline
  makes `ls` output unparseable, and unparseable here means attaching the wrong
  file.
- **Screenshots wait for the compositor** to commit a frame without our surface,
  and animations are force-disabled during a capture.
- **The screensaver and lock surfaces are filtered out** of the window context:
  no context beats confidently wrong context.
- **Motion matches Omarchy** — 140 ms / OutCubic, the duration the shell uses
  most — with no blur and no extra rounding, because Omarchy ships both off.

## Hacking on it

A plugin is a plain git checkout in `~/.config/omarchy/plugins/<id>/`, so clone
it there and edit in place.

Saving a file under that directory triggers a plugin reload, but **an overlay
with `keepLoaded: true` keeps its mounted instance**, so UI edits do not always
appear. When a change seems not to apply:

```bash
omarchy restart shell
```

Third-party plugins run unsandboxed inside `omarchy-shell`. The way back from a
bad change:

```bash
omarchy plugin disable xn4m3d.ask && omarchy restart shell
```

Useful while iterating:

```bash
# the context, without opening anything
omarchy-ask --print-context

# drive the card by hand, with a made-up context
omarchy-shell shell summon xn4m3d.ask '{"window":{"class":"foot"},"cwd":"/tmp"}'
omarchy-shell shell hide xn4m3d.ask

# QML warnings land in the journal
journalctl --user _PID=$(pgrep -f 'quickshell -n -p /usr/share/omarchy/shell') -f
```

Built against **Omarchy 4.0.2** / **Hyprland 0.56.2**.

## License

MIT
