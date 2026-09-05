#!/bin/bash
# docs/themes.png -- the same card under three Omarchy themes.
#
# Nothing in the card names a colour: it is built out of the shell's own
# [menu] surface tokens, which are file-watched. Setting a theme restyles an
# open card without restarting anything, which is what this shows.
cd "$(dirname "$0")" && source ./lib.sh
trap stage_leave EXIT
stage_enter

THEMES=("Solitude" "Tokyo Night" "Catppuccin Latte")
TIGHT="900x360+510+360"

card_open
type_text "what changed in this repo this week?"
sleep 0.5

shots=()
for theme in "${THEMES[@]}"; do
  omarchy-theme-set "$theme" >/dev/null 2>&1
  # The shell watches the theme files rather than being told, so give it a
  # moment to notice and repaint.
  sleep 2.5
  out="$WORK/theme-${theme// /-}.png"
  shot "$out" "$TIGHT"
  shots+=("$out")
done

magick "${shots[@]}" -append "$DOCS/themes.png"
