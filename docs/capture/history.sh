#!/bin/bash
# docs/history.png -- past turns, each carrying its session id.
#
# The list is seeded from a fixture rather than from whatever this machine
# happens to have asked, so the shot is the same every time it is taken. The
# real history is put back afterwards.
cd "$(dirname "$0")" && source ./lib.sh
trap 'restore_history; stage_leave' EXIT
stage_enter

HIST="$HOME/.local/state/omarchy/ask/history.json"
BACKUP="$WORK/history.backup.json"
restore_history() { [[ -f $BACKUP ]] && cp "$BACKUP" "$HIST"; }

[[ -f $HIST ]] && cp "$HIST" "$BACKUP"

now=$(date +%s)
jq -n --argjson t "$now" --arg cwd "$FIXTURE" '[
  {ts: ($t - 240),   prompt: "why is the router dropping keep-alive connections?",
   answer: "The reaper runs on a 30s budget...", agent: "claude",
   cwd: $cwd, sessionId: "b12e72b8-3ff9-4fdd-a197-149d222431c5", attachments: []},
  {ts: ($t - 3600),  prompt: "what does this error in the screenshot mean?",
   answer: "It is a TLS handshake timeout...", agent: "claude",
   cwd: $cwd, sessionId: "5c40a1de-7b02-42a1-9f6b-2d1c8e4a7311", attachments: []},
  {ts: ($t - 9000),  prompt: "summarise what changed in this repo this week",
   answer: "Three areas moved...", agent: "grok",
   cwd: $cwd, sessionId: "01a0701a-d748-7441-b46b-eaf1fc2dd5de", attachments: []},
  {ts: ($t - 90000), prompt: "is Duration::from_secs(30) the right default here?",
   answer: "", agent: "claude",
   cwd: $cwd, sessionId: "", attachments: []}
]' > "$HIST"
sleep 0.8

card_open
key h
sleep 1.0
shot "$DOCS/history.png"
