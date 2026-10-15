#!/bin/bash
# Records an app's tour as a GIF: a short story of using it, with a caption for each step. The same
# recorder serves every Start app; each app supplies a tour file that says what to do.
#
#   scripts/tour.sh TOURFILE [--install] [--yes]
#
#   TOURFILE    a bash file that defines the tour (see "Writing a tour" below), e.g. scripts/tours/hero.sh
#   --install   copy the GIF to the tour's TOUR_OUT in the repo (default: leave it in $TMPDIR and say where)
#   --yes       do not ask first (for when it is run from another script)
#
# How it works. It films a temporary virtual monitor frame by frame with grim, so your own screen is left
# alone, puts a plain backdrop on it, and drives the real pointer and keyboard with ydotool to click through
# the app there. Hands off the mouse and keyboard while it runs: the pointer is on the virtual monitor and
# typing goes to it. So you know, a red window in the middle of your real screen first asks you to confirm
# (Proceed or Cancel) and then stays up saying so, with the step it is on, until it says it is done (a
# notification would show on the virtual monitor, and in the GIF). Whatever the tour changes is put back when
# it ends or is interrupted.
# Needs: hyprctl (Hyprland), jq, grim, ffmpeg (with drawtext), ImageMagick, imv, quickshell, ydotool with its daemon
# running and a writable /dev/uinput. docs/recording-tours.md is the guide.
#
# Writing a tour. A tour file is sourced by this script and defines:
#
#   Variables
#     TOUR_TITLE         the app's name, for the notification            (required)
#     TOUR_OUT           the GIF's path in the repo, e.g. screenshots/hero.gif   (default screenshots/hero.gif)
#     TOUR_LAYER         the layer-shell namespace of the app's window; keys and typing are only sent while
#                        it is up on the virtual monitor, so they never reach anything else   (required to use key/typed/esc)
#     TOUR_STEPS         how many steps (calls to `cap`) it has, for "Step 2 of 6"   (optional)
#     TOUR_SIZE          the virtual monitor, WxH           (default 1280x800)
#     TOUR_BG            the backdrop colour                (default #262a36)
#     TOUR_RESTART_SHELL 1 to restart the Omarchy shell after tour_prepare and again at the end, for tours
#                        whose changes the shell only reads at start     (default 0)
#     TOUR_FONT          the caption font file              (default JetBrains Mono Nerd Font Bold)
#
#   Functions (all optional except tour_play)
#     tour_requires      check what the tour needs; print a reason and return non-zero if it is missing
#     tour_prepare       save what the tour will change, and set up; runs before the first restart
#     tour_setup         runs once the monitor is up and focused, just before filming starts
#     tour_restore       put back whatever tour_prepare/tour_setup/tour_play changed
#     tour_play          the steps, using the helpers below
#
#   Helpers for tour_play (coordinates are on the virtual monitor, 0,0 at its top-left)
#     cap "text"         show this caption from now until the next cap (avoid colons and apostrophes)
#     glide X Y          move the pointer there, in small steps so it is seen to travel
#     click X Y [pause]  glide, click, then wait (default 0.9 s)
#     drag DX DY         press where the pointer is, move by that much, let go
#     typed "text"       type it     key CODE:1 CODE:0 ...   press keys     esc   press Escape
#     wait_until 'cmd' [seconds]    poll a shell command until it succeeds (default 30 s)
#     MON MX W H TMP REPO           the monitor's name, its x in the layout, its size, a scratch folder, the repo root
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
tourfile=${1:-}
install=false
ask=true
for arg in "${@:2}"; do
  case $arg in
    --install) install=true ;;
    --yes) ask=false ;;
    *) echo "tour: unknown option $arg" >&2; exit 2 ;;
  esac
done
[[ -f $tourfile ]] || { echo "tour: usage: scripts/tour.sh TOURFILE [--install] [--yes]" >&2; exit 2; }
tourfile=$(cd "$(dirname "$tourfile")" && pwd)/$(basename "$tourfile")

# shellcheck disable=SC1090
source "$tourfile"
: "${TOUR_TITLE:?the tour file must set TOUR_TITLE}"
: "${TOUR_OUT:=screenshots/hero.gif}"
: "${TOUR_SIZE:=1280x800}"
: "${TOUR_BG:=#262a36}"
: "${TOUR_LAYER:=}"
: "${TOUR_RESTART_SHELL:=0}"
: "${TOUR_FONT:=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf}"
declare -F tour_play >/dev/null || { echo "tour: the tour file must define tour_play" >&2; exit 2; }

MON=TOURREC
W=${TOUR_SIZE%x*}
H=${TOUR_SIZE#*x}
for tool in hyprctl jq grim ffmpeg ffprobe magick imv quickshell ydotool notify-send; do
  command -v "$tool" >/dev/null || { echo "tour: $tool is needed" >&2; exit 1; }
done
if declare -F tour_requires >/dev/null; then tour_requires || exit 1; fi

TMP=$(mktemp -d)
mkdir -p "$TMP/frames"

# ---- the window that asks, and then says it is recording ----------------------------------------
# scripts/tour-banner.qml, run with quickshell: a red window in the middle of the real screen. It redraws in
# place, so it does not flicker. (The shell's notifications and Hyprland's own appear on the focused
# monitor, which is the virtual one while recording, so they would end up in the GIF.)
banner_qml="$HERE/tour-banner.qml"
status="$TMP/status.txt"
orig_mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
banner_pid=""
guide="The pointer is driving a virtual screen and typing goes there."
say() { # LINE: the step it is on; "done" as the first argument says it is over
  if [[ $1 == "done" ]]; then printf 'done\n' >"$status.new"; else printf 'recording\n%s\n' "$1" >"$status.new"; fi
  mv "$status.new" "$status"
}
confirm() { # asks; returns non-zero if the answer is not Proceed
  local answer="$TMP/answer.txt" qpid
  rm -f "$answer"
  TOUR_MODE=confirm TOUR_TITLE=$TOUR_TITLE TOUR_SCREEN=$orig_mon TOUR_ANSWER=$answer \
    quickshell -n -p "$banner_qml" >/dev/null 2>&1 &
  qpid=$!
  while [[ ! -s $answer ]] && kill -0 "$qpid" 2>/dev/null; do sleep 0.2; done
  wait "$qpid" 2>/dev/null
  [[ $(cat "$answer" 2>/dev/null) == proceed ]]
}
start_banner() {
  say "Starting..."
  TOUR_MODE=status TOUR_TITLE=$TOUR_TITLE TOUR_SCREEN=$orig_mon TOUR_STATUS=$status \
    quickshell -n -p "$banner_qml" >/dev/null 2>&1 &
  banner_pid=$!
  sleep 1
  # Putting the window up moves focus to the real screen; the app must open on the virtual one.
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
}
if $ask; then
  confirm || { echo "tour: cancelled, nothing was changed." >&2; rm -rf "$TMP"; exit 0; }
fi
echo "tour: recording. Leave the mouse and keyboard alone until it says it is done." >&2

# ---- putting everything back --------------------------------------------------------------------
read -r orig_cx orig_cy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
rec_pid=""
bg_pid=""
cleanup() {
  [[ -n $rec_pid ]] && kill "$rec_pid" 2>/dev/null
  [[ -n $bg_pid ]] && kill "$bg_pid" 2>/dev/null
  if declare -F tour_restore >/dev/null; then tour_restore; fi
  hyprctl output remove $MON >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$orig_mon\" })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.cursor.move({ x = $orig_cx, y = $orig_cy })" >/dev/null 2>&1
  if [[ $TOUR_RESTART_SHELL == 1 ]]; then
    omarchy-restart-shell >/dev/null 2>&1
    sleep 7
  fi
  # Green, "the tour is done", for a few seconds; then the window goes.
  say done
  notify-send -a "$TOUR_TITLE tour" -u normal -t 8000 "The $TOUR_TITLE tour is done" "You can use the mouse and keyboard again." 2>/dev/null
  sleep 6
  [[ -n $banner_pid ]] && kill "$banner_pid" 2>/dev/null
}
trap cleanup EXIT

# ---- the virtual monitor, and a plain backdrop on it ------------------------------------------------
MX=$(hyprctl monitors -j | jq -r '[.[] | .x + .width] | max')
hyprctl output create headless $MON >/dev/null
hyprctl eval "hl.monitor({ output = \"$MON\", mode = \"${W}x${H}@60\", position = \"${MX}x0\", scale = 1 })" >/dev/null
sleep 1
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
magick -size "${W}x${H}" "xc:$TOUR_BG" "$TMP/bg.png"
imv -f "$TMP/bg.png" >/dev/null 2>&1 &
bg_pid=$!
sleep 1.5
start_banner

if declare -F tour_prepare >/dev/null; then tour_prepare; fi
if [[ $TOUR_RESTART_SHELL == 1 ]]; then
  omarchy-restart-shell >/dev/null 2>&1
  sleep 8
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
  sleep 0.5
fi
if declare -F tour_setup >/dev/null; then tour_setup; fi

# ---- driving the pointer and keys -------------------------------------------------------------
gx=$((W / 2)); gy=$((H / 2))
at() { hyprctl dispatch "hl.dsp.cursor.move({ x = $((MX + $1)), y = $2 })" >/dev/null; ydotool mousemove -x 1 -y 0; ydotool mousemove -x -1 -y 0; gx=$1; gy=$2; }
glide() {
  local i x0=$gx y0=$gy
  for i in 1 2 3 4 5 6 7 8; do at $((x0 + ($1 - x0) * i / 8)) $((y0 + ($2 - y0) * i / 8)); sleep 0.025; done
}
click() { glide "$1" "$2"; sleep 0.35; ydotool click 0xC0 >/dev/null; sleep "${3:-0.9}"; }
drag() {
  local i
  ydotool click 0x40 >/dev/null; sleep 0.2
  for i in 1 2 3 4 5 6 7 8 9 10; do ydotool mousemove -x $(($1 / 10)) -y $(($2 / 10)) >/dev/null; sleep 0.05; done
  sleep 0.2; ydotool click 0x80 >/dev/null; sleep 0.6
}
# Keys and typing only while the app's window is up on the virtual monitor: otherwise they would go to the
# backdrop window.
overlay_up() {
  [[ -n $TOUR_LAYER ]] || return 1
  hyprctl layers -j | jq -e --arg m $MON --arg ns "$TOUR_LAYER" '.[$m] | [.. | .namespace? // empty] | any(. == $ns)' >/dev/null 2>&1
}
key() { if overlay_up; then ydotool key "$@" >/dev/null; else echo "tour: window not up, skipped keys $*" >&2; fi; }
typed() { if overlay_up; then ydotool type --key-delay 45 "$1" >/dev/null; else echo "tour: window not up, skipped typing" >&2; fi; }
esc() { key 1:1 1:0; }
wait_until() { local i; for ((i = 0; i < ${2:-30} * 2; i++)); do eval "$1" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1; }

# ---- recording --------------------------------------------------------------------------------
caps="$TMP/captions.txt"
: >"$caps"
step=0
cap() {
  step=$((step + 1))
  printf '%s|%s\n' "$(date +%s%N)" "$1" >>"$caps"
  say "Step $step${TOUR_STEPS:+ of $TOUR_STEPS}: $1"
}

(while :; do grim -c -t jpeg -q 90 -o $MON "$TMP/frames/$(date +%s%N).jpg"; done) &
rec_pid=$!
sleep 1.5
tour_play
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
echo "tour: recorded $dur s"

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
  vf+="drawtext=fontfile=$TOUR_FONT:text='$text':fontsize=24:fontcolor=white:box=1:boxcolor=0x13151f@0.88:boxborderw=14:x=(w-text_w)/2:y=h-70:enable='between(t,$start,$end)',"
done <"$caps"
ffmpeg -loglevel error -y -ss 1.0 -i "$TMP/tour.mp4" \
  -vf "${vf}fps=10,scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$TMP/tour.gif"
echo "tour: $(du -h "$TMP/tour.gif" | cut -f1)"

if $install; then
  mkdir -p "$(dirname "$REPO/$TOUR_OUT")"
  cp "$TMP/tour.gif" "$REPO/$TOUR_OUT"
  echo "tour: wrote $REPO/$TOUR_OUT"
else
  keep=${TMPDIR:-/tmp}/$(basename "$TOUR_OUT")
  cp "$TMP/tour.gif" "$keep"
  echo "tour: look at $keep, then run again with --install"
fi
