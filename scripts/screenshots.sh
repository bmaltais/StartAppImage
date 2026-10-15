#!/bin/bash
# Retakes the README screenshots in the nested test session (scripts/dev), on a flat dark backdrop.
#
# Nothing touches your real desktop: the session has its own screen, shell and copy of the app data. The view window
# shows what it is doing. Each card is captured with `dev shot` and cropped evenly around the centre of the screen,
# where the windows open. The sandbox's window sizes are reset first, so both windows open at their defaults.
# Needs: scripts/dev (see docs/testing.md), foot, magick (ImageMagick).
#
#   scripts/screenshots.sh [app-id]      app-id is the app whose settings card is shown (default pdfcraft)
#
#   DEV_SIZE=WxH      the session's screen (default 1280x800); the crops are the same, so a bigger screen only adds backdrop
#   SHOTS_OUT=DIR     where the images go (default screenshots/)
set -euo pipefail
APP=${1:-pdfcraft}
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${SHOTS_OUT:-$HERE/screenshots}
DEV=$HERE/scripts/dev
STATE_DIR=${XDG_RUNTIME_DIR:-/run/user/$UID}/startappimage-dev
NEST_HOME=$STATE_DIR/nest/home
BG=2a2f3a
mkdir -p "$OUT"
TMP=$(mktemp -d)
cleanup() { kill "${BGWIN:-}" 2>/dev/null || true; "$DEV" down >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

"$DEV" down >/dev/null 2>&1 || true
"$DEV" up
# shellcheck disable=SC1091
source "$STATE_DIR/state"
nest() { env HOME="$NEST_HOME" XDG_CONFIG_HOME="$NEST_HOME/.config" XDG_DATA_HOME="$NEST_HOME/.local/share" \
  XDG_STATE_HOME="$NEST_HOME/.local/state" XDG_CACHE_HOME="$NEST_HOME/.cache" \
  WAYLAND_DISPLAY="$NWD" HYPRLAND_INSTANCE_SIGNATURE="$NSIG" "$@"; }

# Default window sizes, except a manager tall enough for every app of the sandbox.
nest "$HERE/bin/startappimage" window --reset --reset-setup >/dev/null
nest "$HERE/bin/startappimage" window --size 690x700 >/dev/null

# A ~/Applications of the session's own, so the install card shows "~/Applications" and not the real home. The app's own
# file is a real copy (a symlink to it is resolved to the real folder and shows twice); the rest are links.
ENV_FILE=$NEST_HOME/.local/share/startappimage/$APP.env
CARD_FILE=$(sed -n 's/^EXEC=//p' "$ENV_FILE")
SRC=$(dirname "$CARD_FILE")
if [[ $SRC != "$NEST_HOME/Applications" ]]; then
  mkdir -p "$NEST_HOME/Applications"
  for f in "$SRC"/*.AppImage; do ln -sf "$f" "$NEST_HOME/Applications/${f##*/}"; done
  grep -rIl "$SRC" "$NEST_HOME/.local/share" 2>/dev/null | xargs -r sed -i "s#$SRC#$NEST_HOME/Applications#g"
  CARD_FILE=$NEST_HOME/Applications/${CARD_FILE##*/}
  cp --reflink=auto --remove-destination "$(readlink -f "$CARD_FILE")" "$CARD_FILE"
  "$DEV" reload >/dev/null
fi

# The backdrop: a plain full-screen window inside the session, so no wallpaper, terminal text or cursor shows.
WAYLAND_DISPLAY=$NWD foot --fullscreen -o colors-dark.alpha=1 -o colors-dark.background=$BG \
  -o colors-dark.cursor="$BG $BG" -e sleep 900 >/dev/null 2>&1 &
BGWIN=$!
sleep 2

# shot <name> <out> <width> <height>: capture, then cut a box of that size centred on the screen, with a 40 px margin of backdrop.
shot() {
  "$DEV" shot "$TMP/$1.png" >/dev/null
  local x=$(( (NW - $3) / 2 )) y=$(( (NH - $4) / 2 + 15 ))
  magick "$TMP/$1.png" -crop "$3x$4+$x+$y" +repage -bordercolor "$(magick "$TMP/$1.png" -format '%[pixel:p{5,300}]' info:)" \
    -border 40 "$OUT/$2"
}

"$DEV" open;                          sleep 2; shot manager manager.png 718 730
"$DEV" close; "$DEV" setup;           sleep 2; shot window settings-window.png 790 730
"$DEV" close; "$DEV" settings "$APP"; sleep 2; shot app settings.png 790 730
"$DEV" close
nest "$HERE/bin/startappimage" open "$CARD_FILE" >/dev/null 2>&1
sleep 3; shot card card.png 550 327
echo "Updated $OUT/{manager,settings-window,settings,installed}.png"
