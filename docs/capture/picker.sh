#!/bin/bash
# docs/picker.png -- the file picker, filtered.
cd "$(dirname "$0")" && source ./lib.sh
trap stage_leave EXIT
stage_enter

card_open
type_text "what is this crate missing?"
sleep 0.4
key o            # ctrl+o -- open the picker
sleep 1.0
type_text "ro"   # filter down to router.rs
sleep 0.8
shot "$DOCS/picker.png"
