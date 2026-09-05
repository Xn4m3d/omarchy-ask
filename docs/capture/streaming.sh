#!/bin/bash
# docs/streaming.gif -- a question typed, sent, and answered in place.
#
# The recorder runs behind the driving, so the typing, the wait and the answer
# are one continuous take. Pauses where the picture does not change are dropped
# when the GIF is assembled; nothing that moved is removed.
cd "$(dirname "$0")" && source ./lib.sh
trap stage_leave EXIT
stage_enter

Q="in English, in two sentences: what does a keep-alive timeout do?"
FRAMES="$WORK/streaming"
STOP="$WORK/stop"

card_open
record_frames "$FRAMES" 400 "$STOP" &
recorder=$!

sleep 0.8
type_text "$Q"
sleep 0.6
sent=$(date +%s)
press Return
wait_for_answer "$Q" "$sent" 120
sleep 1.5

touch "$STOP"
wait "$recorder" 2>/dev/null
to_gif "$FRAMES" "$DOCS/streaming.gif" 900
