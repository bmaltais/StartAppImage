#!/bin/bash
# Retakes the README screenshots on a clean background.
#
# It opens an empty workspace with a plain full-screen window behind the cards, so no wallpaper,
# terminal or bar shows around them, captures each state with grim, and trims the result evenly.
# Needs: hyprctl, foot, grim, magick (ImageMagick), and the plugin running in the shell.
# Run it from a terminal on your normal workspace; it puts you back on it afterwards.
#
#   scripts/screenshots.sh [app-id]      app-id is the app whose settings card is shown (default pdfcraft)
#
# For a fair picture, run `startappimage window --reset; startappimage window --reset-setup`
# first and restart the shell (omarchy-restart-shell), so both windows open at their defaults;
# restore your own values afterwards (see `startappimage window`).
set -u
ID=io.github.bmaltais.startappimage
APP=${1:-pdfcraft}
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=$HERE/screenshots
TMP=$(mktemp -d)
BG=2a2f3a
BACK=$(hyprctl activeworkspace -j | jq -r .id)

hyprctl dispatch workspace 7 >/dev/null
foot --fullscreen -o colors.alpha=1 -o colors.background=$BG -o cursor.color="$BG $BG" -e sleep 600 >/dev/null 2>&1 &
BGWIN=$!
sleep 2

# shot <name>: capture, then crop to the card (and its shadow) with an even margin of the backdrop.
shot() {
  grim "$TMP/$1-full.png"
  local c; c=$(magick "$TMP/$1-full.png" -format "%[pixel:p{300,500}]" info:)
  magick "$TMP/$1-full.png" -crop 1700x900+110+110 +repage -fuzz 3% -trim +repage \
    -bordercolor "$c" -border 40 "$OUT/$2"
}

omarchy-shell $ID open;  sleep 2; shot manager manager.png
omarchy-shell $ID setup; sleep 2; shot window settings-window.png
omarchy-shell $ID close; sleep 1
omarchy-shell $ID settings "$APP"; sleep 2; shot app settings.png
omarchy-shell $ID close

kill $BGWIN 2>/dev/null
hyprctl dispatch workspace "$BACK" >/dev/null
rm -rf "$TMP"
echo "Updated $OUT/{manager,settings-window,settings}.png"
