#!/bin/bash
# docs/settings.png -- everything the card does, and the switch for it.
cd "$(dirname "$0")" && source ./lib.sh
trap stage_leave EXIT
stage_enter

card_open
key comma
sleep 1.0
shot "$DOCS/settings.png"
