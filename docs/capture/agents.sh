#!/bin/bash
# docs/agents.gif -- ctrl+shift+a walking through the agents installed here.
#
# What it shows depends on the machine: the switch offers what `mise` reports
# as installed, so a machine with one agent has nothing to record.
cd "$(dirname "$0")" && source ./lib.sh
trap stage_leave EXIT
stage_enter

count=$(omarchy-ask-agents | wc -l)
((count > 1)) || { echo "only $count agent installed; nothing to show" >&2; exit 0; }

FRAMES="$WORK/agents"
STOP="$WORK/stop"

card_open
type_text "which of you knows this codebase best?"
sleep 0.5

record_frames "$FRAMES" 120 "$STOP" &
recorder=$!
sleep 1.0
for _ in $(seq 1 "$count"); do
  wtype -M ctrl -M shift -k a -m shift -m ctrl
  sleep 1.4
done
touch "$STOP"
wait "$recorder" 2>/dev/null

to_gif "$FRAMES" "$DOCS/agents.gif" 900
