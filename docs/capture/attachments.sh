#!/bin/bash
# docs/attachments.gif -- the clipboard and a file becoming chips on a question.
#
# Every attachment is an explicit keystroke. A clipboard that shipped with
# every question would eventually ship a password, so nothing is attached
# unless you asked for it.
cd "$(dirname "$0")" && source ./lib.sh
trap stage_leave EXIT
stage_enter

printf 'thread "tokio-runtime-worker" panicked at src/pool.rs:88\n' | wl-copy

FRAMES="$WORK/attach"
STOP="$WORK/stop"

card_open
record_frames "$FRAMES" 200 "$STOP" &
recorder=$!

sleep 0.8
type_text "what is going on here?"
sleep 0.8
wtype -M ctrl -M shift -k v -m shift -m ctrl   # attach the clipboard
sleep 1.6
key o                                          # open the file picker
sleep 1.2
type_text "src"
sleep 0.6
press Return                                   # into src/
sleep 1.0
type_text "pool"
sleep 0.8
press Return                                   # attach src/pool.rs
sleep 2.0

touch "$STOP"
wait "$recorder" 2>/dev/null
to_gif "$FRAMES" "$DOCS/attachments.gif" 900
