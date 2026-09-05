#!/bin/bash
# docs/card.png -- the composer, with the context it picked up on its own.
#
# Full frame rather than a crop: the point of this one is that the card floats
# over whatever you were doing, so the desktop around it is the subject too.
cd "$(dirname "$0")" && source ./lib.sh
trap stage_leave EXIT
stage_enter

card_open
type_text "why is the router dropping keep-alive connections?"
sleep 0.7
shot "$DOCS/card.png" full
