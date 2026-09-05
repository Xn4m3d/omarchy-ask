# docs

Every image here is a real capture of the plugin running on a real Omarchy
desktop. Nothing is mocked, and nothing is drawn by hand — which is why the
scripts that produced them are in [`capture/`](capture/) rather than lost in a
shell history.

| File | Shows | Made by |
|---|---|---|
| [`card.png`](card.png) | the composer with the context it picked up | [`capture/card.sh`](capture/card.sh) |
| [`streaming.gif`](streaming.gif) | a question typed, sent, and answered in place | [`capture/streaming.sh`](capture/streaming.sh) |
| [`attachments.gif`](attachments.gif) | the clipboard and a file becoming chips | [`capture/attachments.sh`](capture/attachments.sh) |
| [`agents.gif`](agents.gif) | `ctrl+shift+a` walking through the installed agents | [`capture/agents.sh`](capture/agents.sh) |
| [`picker.png`](picker.png) | the file picker, narrowed by typing | [`capture/picker.sh`](capture/picker.sh) |
| [`history.png`](history.png) | past turns, with their agent and age | [`capture/history.sh`](capture/history.sh) |
| [`settings.png`](settings.png) | the settings screen | [`capture/settings.sh`](capture/settings.sh) |
| [`themes.png`](themes.png) | the same card under three Omarchy themes | [`capture/themes.sh`](capture/themes.sh) |

## Regenerating them

```bash
docs/capture/card.sh        # any one of them
```

Each script is standalone. It takes over the screen for as long as it runs — it
types into the card with `wtype` — so do not use the machine while one is going.

Beyond what Omarchy already ships (`grim`, `jq`, `hyprland`), they need `wtype`
to type and `ffmpeg` + `imagemagick` to crop and assemble:

```bash
sudo pacman -S --needed wtype ffmpeg imagemagick
```

## What the scripts do to your session, and put back

They stage an empty workspace and restore the one you were on. They keep the
screen awake while recording and restore the idle setting. `themes.sh` changes
the Omarchy theme and sets it back; `agents.sh` walks through your installed
agents and puts `~/.config/omarchy/ask.json` back as it found it;
`history.sh` swaps in a fixture history and restores the real one. A throwaway
project is created at `~/Projects/pathfinder` and removed, unless one is
already there — in which case yours is used and left alone.

The card is a layer-shell surface over a dimmed screen, so whatever sits behind
it lands in the shot. That is the reason for the empty workspace: on a working
machine the background is your actual work.

## Two things to be straight about

**The recordings collapse their own dead air.** Frames identical to the one
before them are dropped when the GIF is assembled, which mostly means the wait
between sending a question and the first token. Nothing that moved is removed,
and no frame is reordered or sped up. Model latency is real and depends on your
setup — `streaming.gif` is not a benchmark.

**The context in the shots is passed in, not captured.** The scripts hand the
overlay the same JSON payload `omarchy-ask` builds from `hyprctl activewindow`,
so the chips do not depend on which window happened to be focused when you ran
the script. It is the real code path with a fixed input.

## Not captured here

The region picker (`ctrl+r`) freezes the screen and asks you to drag a
rectangle. There is no synthetic mouse in this setup, so it is the one feature
with no recording — the keyboard-driven attachments in `attachments.gif` go
through exactly the same chip-and-path plumbing.
