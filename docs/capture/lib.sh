#!/bin/bash

# Shared helpers for the documentation captures.
#
# Nothing here is mocked. Each script drives the real plugin on a real Omarchy
# session: the card is summoned over the shell's IPC with a context payload,
# driven with wtype, and photographed with grim. That is the whole reason these
# live in the repo -- a contributor can regenerate every asset under docs/ with
# one command instead of trusting screenshots they cannot reproduce.
#
# Requires, beyond what Omarchy already ships (grim, jq, hyprland): wtype to
# type into the card, and ffmpeg + imagemagick to crop and assemble. All three
# are in the Arch repos.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCS="$REPO/docs"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ask-capture.XXXXXX")"

PLUGIN_ID="xn4m3d.ask"

# An empty workspace. The card is a layer-shell surface over a dimmed screen,
# so whatever sits behind it lands in the shot -- including, on a working
# machine, whatever you were actually doing.
STAGE_WS="${ASK_CAPTURE_WS:-5}"

# A throwaway project, so the directory chip has something plausible to show
# and questions about "this repo" have an answer. Created and removed by
# stage_enter/stage_leave.
FIXTURE="${ASK_CAPTURE_FIXTURE:-$HOME/Projects/pathfinder}"

# Frames per second for the recordings. grim needs ~57ms per full-screen frame
# on a 1080p laptop, so 10 leaves headroom; going much above 12 starts dropping.
FPS="${ASK_CAPTURE_FPS:-10}"

# The card, plus a comfortable margin, in PHYSICAL pixels of a 1920x1080 frame.
# See the note on grim geometry in shot() before changing this.
CROP="${ASK_CAPTURE_CROP:-1200x700+360+190}"

# ---------------------------------------------------------------- compositor

# Omarchy 4 configures Hyprland in Lua, and `hyprctl dispatch` evaluates its
# argument as Lua rather than as the classic `dispatcher arg` string. The old
# syntax fails with a parse error, not a no-op, which is easy to miss when the
# call is redirected to /dev/null.
hypr() { hyprctl dispatch "$1" >/dev/null 2>&1; }

focus_ws() { hypr "hl.dsp.focus({ workspace = \"$1\" })"; }

# ------------------------------------------------------------------- staging

_saved_ws=""
_saved_agent=""
_saved_theme=""
_saved_awake=""
_made_fixture=0

stage_enter() {
  for tool in grim wtype ffmpeg magick jq; do
    command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
  done

  _saved_ws=$(hyprctl activeworkspace -j | jq -r '.id')
  _saved_agent=$(omarchy-default-agent)
  _saved_theme=$(omarchy-theme-current)

  # A screensaver halfway through a recording is a wasted take.
  _saved_awake=$([[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]] && echo on || echo off)
  omarchy-toggle-idle stay-awake >/dev/null

  if [[ ! -d $FIXTURE ]]; then
    _made_fixture=1
    mkdir -p "$FIXTURE/src"
    cat >"$FIXTURE/Cargo.toml" <<'EOF'
[package]
name = "pathfinder"
version = "0.3.1"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
hyper = "1"
EOF
    cat >"$FIXTURE/src/router.rs" <<'EOF'
use std::time::Duration;

/// Per-connection keep-alive budget. Connections idle past this are reaped.
pub const KEEP_ALIVE: Duration = Duration::from_secs(30);

pub struct Router {
    routes: Vec<Route>,
    keep_alive: Duration,
}
EOF
    printf '# pathfinder\n' >"$FIXTURE/README.md"
  fi

  focus_ws "$STAGE_WS"
  sleep 0.8
}

stage_leave() {
  card_close
  [[ -n $_saved_ws ]] && focus_ws "$_saved_ws"
  # Only when actually changed: setting the default agent opens an agent
  # terminal, which would land in the middle of the next capture.
  [[ -n $_saved_agent && $_saved_agent != "$(omarchy-default-agent)" ]] \
    && omarchy-default-agent "$_saved_agent" >/dev/null 2>&1
  [[ -n $_saved_theme && $_saved_theme != "$(omarchy-theme-current)" ]] \
    && omarchy-theme-set "$_saved_theme" >/dev/null 2>&1
  [[ $_saved_awake == "off" ]] && omarchy-toggle-idle allow-idle >/dev/null
  ((_made_fixture)) && rm -rf "$FIXTURE"
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------- card

# The context the wrapper would have collected from a real focused window. It
# is passed verbatim, which is what makes a capture reproducible: the chips do
# not depend on which window happened to be focused when you ran the script.
context_payload() {
  jq -nc --arg cwd "$FIXTURE" --arg title "${1:-nvim src/router.rs}" \
    '{window: {class: "foot", title: $title, address: "0x0", pid: 0,
               workspace: "", geometry: ""},
      cwd: $cwd, restore: ""}'
}

card_open() {
  omarchy-shell shell summon "$PLUGIN_ID" "$(context_payload "${1:-}")" >/dev/null 2>&1
  sleep 0.8
}

card_close() {
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1
  sleep 0.4
}

# wtype remaps the virtual keyboard per character, so this is layout
# independent -- it types the same on azerty and qwerty. The delay is not
# cosmetic: typing a sentence with no gap at all outruns the text field and
# loses the tail of it. It also makes the typing legible in a recording.
type_text() { wtype -d "${TYPE_DELAY:-28}" "$1"; }
key() { wtype -M "${2:-ctrl}" -k "$1" -m "${2:-ctrl}"; }
press() { wtype -k "$1"; }

# ------------------------------------------------------------------- capture

# grim's -g geometry is in LOGICAL pixels, which on a scaled output is not the
# size of the file it writes: this 1920x1080 panel at scale 1.25 is 1536x864
# logically. Cropping after the fact with magick keeps every offset in the same
# units as the image, which is one less thing to get wrong.
shot() {
  local out=$1 crop=${2:-$CROP}
  grim -l 1 "$WORK/raw.png"
  if [[ $crop == "full" ]]; then
    magick "$WORK/raw.png" -resize 1600x "$out"
  else
    magick "$WORK/raw.png" -crop "$crop" +repage "$out"
  fi
}

# Record until the caller's condition script says stop, or the frame budget
# runs out. Frames are numbered so ffmpeg can read them as a sequence.
record_frames() {
  local dir=$1 max=$2
  mkdir -p "$dir"
  local i=0
  while ((i < max)); do
    grim -l 0 "$(printf '%s/f%04d.png' "$dir" "$i")"
    ((i++))
    sleep "$(awk -v f="$FPS" 'BEGIN{print 1/f}')"
  done
}

# Two passes: a palette built from the whole clip, then the clip mapped onto
# it. One pass with the default 216-colour web palette turns a photographic
# wallpaper into mud.
to_gif() {
  local dir=$1 out=$2 width=${3:-900}
  local filters="crop=${CROP%%+*}:${CROP#*+}"
  filters="crop=$(echo "$CROP" | sed 's/x/:/;s/+/:/g'),scale=$width:-1:flags=lanczos"
  ffmpeg -y -loglevel error -framerate "$FPS" -i "$dir/f%04d.png" \
    -vf "$filters,palettegen=stats_mode=diff" "$WORK/pal.png" || return 1
  ffmpeg -y -loglevel error -framerate "$FPS" -i "$dir/f%04d.png" -i "$WORK/pal.png" \
    -lavfi "$filters [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=3" \
    -loop 0 "$out"
}
