#!/bin/bash
# Records the tour at the top of the README (screenshots/hero.gif): a short story of using StartAppImage,
# with a caption for each step.
#
#   scripts/hero.sh [--install]      --install copies the GIF to screenshots/hero.gif (default: leave it
#                                    in a temporary folder and say where)
#
# It films a temporary virtual monitor (1280x800) frame by frame with grim, so your own screen is left
# alone, and drives the real pointer and keyboard with ydotool to click through the app on that monitor.
# Hands off the mouse and keyboard while it runs (about two minutes): the pointer is on the virtual
# monitor, and typing goes to it.
#
# While it runs it: resets the manager's and the settings window's saved size and place to the defaults
# (and restarts the shell, twice); makes ArtCraft look one version behind so the tour can update it (the
# update downloads the real release, 12 MB, to the same file); changes the update check interval and
# switches the bar icon off and on again. Everything is put back when it ends or is interrupted.
# Needs: hyprctl, jq, grim, ffmpeg (with drawtext), ImageMagick, imv, ydotool and a writable /dev/uinput
# (see docs/ui-standards.md "Verifying a UI change"), the plugin installed and running, and the apps this
# tour uses installed from StartAppImage's list: ArtCraft Launcher (with a GitHub source) and PdfCraft.
set -u

ID=io.github.bmaltais.startappimage
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI=$HOME/.config/omarchy/plugins/$ID/bin/startappimage
ARTENV=$HOME/.local/share/startappimage/artcraft-launcher.env
APPIMG=$(ls "$HOME"/Applications/pdfcraft-*.AppImage 2>/dev/null | head -n1)
MON=HEROREC
W=1280
H=800
FONT=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf
install=false
[[ ${1:-} == --install ]] && install=true

for tool in hyprctl jq grim ffmpeg magick imv ydotool; do
  command -v "$tool" >/dev/null || { echo "hero: $tool is needed" >&2; exit 1; }
done
[[ -x $CLI ]] || { echo "hero: the plugin is not installed at $CLI" >&2; exit 1; }
[[ -f $ARTENV ]] || { echo "hero: ArtCraft Launcher is not installed from StartAppImage" >&2; exit 1; }
[[ -n $APPIMG ]] || { echo "hero: no ~/Applications/pdfcraft-*.AppImage to open" >&2; exit 1; }

TMP=$(mktemp -d)
mkdir -p "$TMP/frames"

# ---- what to put back ---------------------------------------------------------------------------
orig_mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
read -r orig_cx orig_cy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
orig_win=$("$CLI" window)
orig_info=$("$CLI" integration)
cp "$ARTENV" "$TMP/artcraft.env"
rec_pid=""
bg_pid=""

cleanup() {
  [[ -n $rec_pid ]] && kill "$rec_pid" 2>/dev/null
  [[ -n $bg_pid ]] && kill "$bg_pid" 2>/dev/null
  omarchy-shell -q $ID close 2>/dev/null
  cp "$TMP/artcraft.env" "$ARTENV"
  "$CLI" setup --bar-icon "$(jq -r .barIcon <<<"$orig_info")" --check-hours "$(jq -r .checkHours <<<"$orig_info")" >/dev/null 2>&1
  "$CLI" window --size "$(jq -r '"\(.w)x\(.h)"' <<<"$orig_win")" --offset "$(jq -r '"\(.x),\(.y)"' <<<"$orig_win")" \
    --setup-size "$(jq -r '"\(.setup.w)x\(.setup.h)"' <<<"$orig_win")" --setup-offset "$(jq -r '"\(.setup.x),\(.setup.y)"' <<<"$orig_win")" >/dev/null 2>&1
  hyprctl output remove $MON >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$orig_mon\" })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.cursor.move({ x = $orig_cx, y = $orig_cy })" >/dev/null 2>&1
  "$CLI" check >/dev/null 2>&1
  omarchy-restart-shell >/dev/null 2>&1
}
trap cleanup EXIT

# ---- the virtual monitor, and a plain backdrop on it ------------------------------------------------
MX=$(hyprctl monitors -j | jq -r '[.[] | .x + .width] | max')
hyprctl output create headless $MON >/dev/null
hyprctl eval "hl.monitor({ output = \"$MON\", mode = \"${W}x${H}@60\", position = \"${MX}x0\", scale = 1 })" >/dev/null
sleep 1
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
magick -size ${W}x${H} xc:'#262a36' "$TMP/bg.png"
imv -f "$TMP/bg.png" >/dev/null 2>&1 &
bg_pid=$!
sleep 1.5

# Both windows start where the defaults put them, and the shell picks that up on a restart.
"$CLI" window --reset >/dev/null
"$CLI" window --reset-setup >/dev/null
omarchy-restart-shell >/dev/null 2>&1
sleep 8
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
sleep 0.5

# ArtCraft looks one version behind, so the tour has something to update.
sed -i 's/^VERSION=.*/VERSION=v0.4.0/' "$ARTENV"

# ---- driving the pointer and keys -------------------------------------------------------------
gx=640; gy=400
at() { hyprctl dispatch "hl.dsp.cursor.move({ x = $((MX + $1)), y = $2 })" >/dev/null; ydotool mousemove -x 1 -y 0; ydotool mousemove -x -1 -y 0; gx=$1; gy=$2; }
glide() { # X Y: move there in small steps, so the pointer is seen to travel
  local i x0=$gx y0=$gy
  for i in 1 2 3 4 5 6 7 8; do at $((x0 + ($1 - x0) * i / 8)) $((y0 + ($2 - y0) * i / 8)); sleep 0.025; done
}
click() { glide "$1" "$2"; sleep 0.35; ydotool click 0xC0 >/dev/null; sleep "${3:-0.9}"; }
# Keys and typing only while the app's window is up on the virtual monitor: otherwise they would go to the
# backdrop window.
overlay_up() { hyprctl layers -j | jq -e --arg m $MON '.[$m] | [.. | .namespace? // empty] | any(. == "omarchy-startappimage")' >/dev/null 2>&1; }
key() { overlay_up && ydotool key "$@" >/dev/null || echo "hero: window not up, skipped keys $*" >&2; }
typed() { overlay_up && ydotool type --key-delay 45 "$1" >/dev/null || echo "hero: window not up, skipped typing" >&2; }
esc() { key 1:1 1:0; }
drag() { # DX DY: hold the button where the pointer is, move by that much, let go
  local i
  ydotool click 0x40 >/dev/null; sleep 0.2
  for i in 1 2 3 4 5 6 7 8 9 10; do ydotool mousemove -x $(($1 / 10)) -y $(($2 / 10)) >/dev/null; sleep 0.05; done
  sleep 0.2; ydotool click 0x80 >/dev/null; sleep 0.6
}

# ---- recording --------------------------------------------------------------------------------
caps="$TMP/captions.txt"
: >"$caps"
cap() { printf '%s|%s\n' "$(date +%s%N)" "$1" >>"$caps"; }

(while :; do grim -c -t jpeg -q 90 -o $MON "$TMP/frames/$(date +%s%N).jpg"; done) &
rec_pid=$!
sleep 1.5

# 1. Double-click an AppImage: the card says what it is before it runs.
cap "Double-click an AppImage. See what it is before it runs"
omarchy-shell $ID install "$APPIMG"
sleep 1.6
glide 500 515; sleep 0.5
glide 706 515; sleep 0.7
glide 820 515; sleep 1.6
esc; sleep 0.8

# 2. The manager: everything installed, with an update waiting.
cap "Everything you installed, in one place. Updates at a glance"
omarchy-shell $ID open
sleep 1.4
glide 640 330; glide 640 480; sleep 0.4
glide 640 300; sleep 2.6

# 3. One click to update.
cap "One click to update"
click 766 288 0.5
for _ in $(seq 1 60); do grep -q '^VERSION=v0.4.1' "$ARTENV" 2>/dev/null && break; sleep 0.5; done
sleep 2.4

# 4. Point an app at its GitHub releases; the link is checked as you type.
cap "Point an app at its GitHub releases. The link is checked as you type"
click 862 567 1.4
click 309 311 0.8
click 737 318 0.5
typed "https://github.com/storytold/craft-launcher/releases"
sleep 3.8
esc; sleep 1.2

# 5. Settings apply the moment you change them.
cap "Settings apply the moment you change them"
click 536 146 1.4
click 309 351 0.8
click 876 289 1.1       # Daily
click 822 289 1.0       # back to 6 hours
click 309 311 0.8       # Bar
click 980 276 1.8       # bar icon off: it leaves the bar
click 980 276 1.8       # and on again
click 640 170 0.5
typed "remember"
sleep 2.2
esc; sleep 0.6
esc; sleep 1.0

# 6. Move it, resize it, and it comes back where it was left.
cap "Resize it, move it. It opens where you left it"
glide 951 681; sleep 0.4
drag 130 30
glide 760 142; sleep 0.4
drag -170 -10
sleep 1.0
esc; sleep 1.0
omarchy-shell $ID open
sleep 2.6
esc; sleep 1.0

kill "$rec_pid" 2>/dev/null; wait "$rec_pid" 2>/dev/null
rec_pid=""

# ---- the GIF ------------------------------------------------------------------------------------
frames=$(ls "$TMP/frames"/*.jpg | sort)
first=$(basename "$(echo "$frames" | head -n1)" .jpg)
prev=""; prev_t=""
: >"$TMP/frames.txt"
for f in $frames; do
  [[ -s $f ]] || continue
  t=$(basename "$f" .jpg)
  [[ -n $prev ]] && printf 'duration %s\n' "$(awk -v a="$prev_t" -v b="$t" 'BEGIN { printf "%.3f", (b - a) / 1e9 }')" >>"$TMP/frames.txt"
  printf "file '%s'\n" "$f" >>"$TMP/frames.txt"
  prev=$f; prev_t=$t
done
printf "file '%s'\n" "$prev" >>"$TMP/frames.txt"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$TMP/frames.txt" -fps_mode vfr -c:v libx264 -pix_fmt yuv420p -crf 14 "$TMP/tour.mp4"
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/tour.mp4")
echo "hero: recorded $dur s"

# A caption shows from when it was said until the next one, or the end.
vf=""
n=$(wc -l <"$caps")
i=0
while IFS='|' read -r ts text; do
  i=$((i + 1))
  start=$(awk -v a="$first" -v b="$ts" 'BEGIN { printf "%.2f", (b - a) / 1e9 }')
  if [[ $i -lt $n ]]; then
    nxt=$(sed -n "$((i + 1))p" "$caps" | cut -d'|' -f1)
    end=$(awk -v a="$first" -v b="$nxt" 'BEGIN { printf "%.2f", (b - a) / 1e9 - 0.15 }')
  else
    end=$dur
  fi
  vf+="drawtext=fontfile=$FONT:text='$text':fontsize=24:fontcolor=white:box=1:boxcolor=0x13151f@0.88:boxborderw=14:x=(w-text_w)/2:y=h-70:enable='between(t,$start,$end)',"
done <"$caps"
ffmpeg -loglevel error -y -ss 1.0 -i "$TMP/tour.mp4" \
  -vf "${vf}fps=10,scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$TMP/hero.gif"
echo "hero: hero.gif $(du -h "$TMP/hero.gif" | cut -f1)"

if $install; then
  cp "$TMP/hero.gif" "$REPO/screenshots/hero.gif"
  echo "hero: wrote $REPO/screenshots/hero.gif"
else
  keep=${TMPDIR:-/tmp}/startappimage-hero.gif
  cp "$TMP/hero.gif" "$keep"
  echo "hero: look at $keep, then run again with --install"
fi
