#!/bin/bash
# Records an app's tour as a GIF: a short story of using it, with a caption for each step. The same
# recorder serves every Start app; each app supplies a tour file that says what to do.
#
#   scripts/tour.sh TOURFILE [--install] [--yes] [--nested]
#
#   TOURFILE    a bash file that defines the tour (see "Writing a tour" below), e.g. scripts/tours/hero.sh
#   --install   copy the result to the tour's TOUR_OUT in the repo (default: leave it in $TMPDIR and say where)
#   --yes       do not ask first (for when it is run from another script)
#   --nested    run the tour in a nested session shown in a window on your screen, instead of on a hidden virtual
#               monitor: you can watch it, your mouse and keyboard cannot reach it, and it changes only a sandbox,
#               never your real settings or files. See scripts/nested/session.sh and docs/recording-tours.md.
#
# How it works. It films a temporary virtual monitor frame by frame with grim, so your own screen is left
# alone, puts a plain backdrop on it, and drives the real pointer and keyboard with ydotool to click through
# the app there. Hands off the mouse and keyboard while it runs: the pointer is on the virtual monitor and
# typing goes to it. So you know, a red window in the middle of your real screen first asks you to confirm
# (Proceed or Cancel) and then stays up saying so, with the step it is on, until it says it is done (a
# notification would show on the virtual monitor, and in the GIF). Whatever the tour changes is put back when
# it ends or is interrupted.
# Needs: hyprctl (Hyprland), jq, grim, ffmpeg (with drawtext), ImageMagick, imv, quickshell, and ydotool with its
# daemon running and a writable /dev/uinput (not for --nested, which needs wtype, gcc and wayland-scanner instead).
# docs/recording-tours.md is the guide.
#
# Writing a tour. A tour file is sourced by this script and defines:
#
#   Variables
#     TOUR_TITLE         the app's name, for the notification            (required)
#     TOUR_OUT           the result's path in the repo; its extension picks the format, .avif (animated AVIF, small) or
#                        .gif                                                       (default screenshots/hero.avif)
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
NESTED=false
for arg in "${@:2}"; do
  case $arg in
    --install) install=true ;;
    --yes) ask=false ;;
    --nested) NESTED=true ;;
    *) echo "tour: unknown option $arg" >&2; exit 2 ;;
  esac
done
[[ -f $tourfile ]] || { echo "tour: usage: scripts/tour.sh TOURFILE [--install] [--yes] [--nested]" >&2; exit 2; }
tourfile=$(cd "$(dirname "$tourfile")" && pwd)/$(basename "$tourfile")

# shellcheck disable=SC1090
source "$tourfile"
: "${TOUR_TITLE:?the tour file must set TOUR_TITLE}"
: "${TOUR_OUT:=screenshots/hero.avif}"
: "${TOUR_SIZE:=1280x800}"
: "${TOUR_BG:=#262a36}"
: "${TOUR_LAYER:=}"
: "${TOUR_RESTART_SHELL:=0}"
: "${TOUR_FONT:=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf}"
declare -F tour_play >/dev/null || { echo "tour: the tour file must define tour_play" >&2; exit 2; }

MON=TOURREC
W=${TOUR_SIZE%x*}
H=${TOUR_SIZE#*x}
for tool in hyprctl jq grim ffmpeg ffprobe magick imv quickshell notify-send; do
  command -v "$tool" >/dev/null || { echo "tour: $tool is needed" >&2; exit 1; }
done
$NESTED || command -v ydotool >/dev/null || { echo "tour: ydotool is needed (or use --nested)" >&2; exit 1; }
if declare -F tour_requires >/dev/null; then tour_requires || exit 1; fi

TMP=$(mktemp -d)
mkdir -p "$TMP/frames"
if $NESTED; then
  # shellcheck source=nested/session.sh
  source "$HERE/nested/session.sh"
  nested_requires || exit 1
fi

# ---- the window that asks, and then says it is recording ----------------------------------------
# scripts/tour-banner.qml, run with quickshell: a red window in the middle of the real screen. It redraws in
# place, so it does not flicker. (The shell's notifications and Hyprland's own appear on the focused
# monitor, which is the virtual one while recording, so they would end up in the GIF.)
banner_qml="$HERE/tour-banner.qml"
status="$TMP/status.txt"
orig_mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
banner_pid=""
guide="The pointer is driving a virtual screen and typing goes there."
say() { # [STATE] TEXT: the step it is on. STATE is starting, encoding, cancelled or done; without one it is "recording"
  local state=recording
  case $1 in starting | encoding | cancelled | done) state=$1; shift ;; esac
  printf '%s\n%s\n' "$state" "$*" >"$status.new"
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
# Your real home and XDG directories, as they are now: in --nested mode the sandbox's replace them, and this window
# must not carry those (it would be taken for part of the nested session and stopped with it).
real_home=$HOME
real_xdg_config=${XDG_CONFIG_HOME:-$HOME/.config}
real_xdg_data=${XDG_DATA_HOME:-$HOME/.local/share}
real_xdg_state=${XDG_STATE_HOME:-$HOME/.local/state}
real_xdg_cache=${XDG_CACHE_HOME:-$HOME/.cache}
start_banner() {
  say starting "Starting the nested desktop..."
  env HOME="$real_home" XDG_CONFIG_HOME="$real_xdg_config" XDG_DATA_HOME="$real_xdg_data" \
    XDG_STATE_HOME="$real_xdg_state" XDG_CACHE_HOME="$real_xdg_cache" \
    TOUR_MODE=status TOUR_TITLE=$TOUR_TITLE TOUR_SCREEN=$orig_mon TOUR_STATUS=$status TOUR_ANSWER="$TMP/cancel.txt" \
    TOUR_NESTED=$($NESTED && echo 1 || echo 0) TOUR_SHIELD=${SHIELD:-0,0,0,0} \
    TOUR_STRIP_GAP=${NEST_STRIP_GAP:-24} TOUR_STRIP_H=${NEST_STRIP_H:-170} \
    quickshell -n -p "$banner_qml" >/dev/null 2>&1 &
  banner_pid=$!
  # The Cancel button writes to a file; this ends the run when it does (which puts everything back, see cleanup).
  if $NESTED; then
    ( while [[ ! -s $TMP/cancel.txt ]]; do sleep 0.3; done; kill -TERM $$ 2>/dev/null ) &
    cancel_watch=$!
  fi
  sleep 1
  # Putting the window up moves focus to the real screen; the app must open on the virtual one.
  $NESTED || hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
}
if $ask; then
  confirm || { echo "tour: cancelled, nothing was changed." >&2; rm -rf "$TMP"; exit 0; }
fi
echo "tour: recording. Leave the mouse and keyboard alone until it says it is done." >&2

# ---- putting everything back --------------------------------------------------------------------
read -r orig_cx orig_cy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
rec_pid=""
bg_pid=""
released=false
cancelled=false
cancel_watch=""
# Gives you your screen, mouse and keyboard back: stops filming, ends the nested session or puts the real app and the
# virtual monitor back. Done as soon as the filming stops, not after the GIF is built.
release() {
  $released && return
  released=true
  [[ -n $cancel_watch ]] && kill "$cancel_watch" 2>/dev/null
  [[ -n $rec_pid ]] && kill "$rec_pid" 2>/dev/null
  rec_pid=""
  [[ -n $bg_pid ]] && kill "$bg_pid" 2>/dev/null
  if $NESTED; then
    # Only the sandbox was changed, and it is thrown away with the session: nothing of yours to put back.
    nested_stop
  else
    if declare -F tour_restore >/dev/null; then tour_restore; fi
    hyprctl output remove $MON >/dev/null 2>&1
    hyprctl dispatch "hl.dsp.focus({ monitor = \"$orig_mon\" })" >/dev/null 2>&1
    hyprctl dispatch "hl.dsp.cursor.move({ x = $orig_cx, y = $orig_cy })" >/dev/null 2>&1
    if [[ $TOUR_RESTART_SHELL == 1 ]]; then
      omarchy-restart-shell >/dev/null 2>&1
      sleep 7
    fi
  fi
}
cleanup() {
  release
  if $cancelled; then
    say cancelled "Cancelled"
    notify-send -a "$TOUR_TITLE tour" -u normal -t 8000 "The $TOUR_TITLE tour was cancelled" "Nothing was kept. You can use the mouse and keyboard again." 2>/dev/null
    echo "tour: cancelled, nothing was kept." >&2
  else
    # Green, "the tour is done", for a few seconds; then the window goes.
    say "done"
    notify-send -a "$TOUR_TITLE tour" -u normal -t 8000 "The $TOUR_TITLE tour is done" "You can use the mouse and keyboard again." 2>/dev/null
  fi
  sleep 6
  [[ -n $banner_pid ]] && kill "$banner_pid" 2>/dev/null
}
trap cleanup EXIT
# Ctrl+C, or the Cancel button: stop at once; the EXIT trap puts everything back.
trap 'cancelled=true; exit 130' INT TERM

magick -size "${W}x${H}" "xc:$TOUR_BG" "$TMP/bg.png"
if $NESTED; then
  # ---- a nested session in a window, in a sandbox --------------------------------------------------
  prev_focus=$(hyprctl activewindow -j | jq -r '.address // empty')
  sandbox_build || exit 1
  sandbox_enter
  if declare -F tour_prepare >/dev/null; then tour_prepare; fi
  nested_start || exit 1
  nested_place "$prev_focus"
  start_banner
  nested_wait_ready
  nested_enter
  CAPMON=$NMON
  # The nested shell draws the theme's wallpaper, so it looks like a real Omarchy desktop. TOUR_BACKDROP=plain
  # puts the flat TOUR_BG colour over it instead (as the virtual monitor mode always does).
  if [[ ${TOUR_BACKDROP:-wallpaper} == plain ]]; then
    imv -f "$TMP/bg.png" >/dev/null 2>&1 &
    bg_pid=$!
  fi
  sleep 1.5
  if declare -F tour_setup >/dev/null; then tour_setup; fi
else
# ---- the virtual monitor, and a plain backdrop on it ------------------------------------------------
MX=$(hyprctl monitors -j | jq -r '[.[] | .x + .width] | max')
hyprctl output create headless $MON >/dev/null
hyprctl eval "hl.monitor({ output = \"$MON\", mode = \"${W}x${H}@60\", position = \"${MX}x0\", scale = 1 })" >/dev/null
sleep 1
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
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
  CAPMON=$MON
fi

# ---- driving the pointer and keys -------------------------------------------------------------
gx=$((W / 2)); gy=$((H / 2))
at() {
  if $NESTED; then nest_at "$1" "$2"
  else hyprctl dispatch "hl.dsp.cursor.move({ x = $((MX + $1)), y = $2 })" >/dev/null; ydotool mousemove -x 1 -y 0; ydotool mousemove -x -1 -y 0
  fi
  gx=$1; gy=$2
}

# ---- human-like input -------------------------------------------------------------------------------
# A person does not move in straight lines at a steady speed or type like a metronome. With TOUR_HUMAN=1 (the default)
# the pointer and keys behave the way the research and the existing emulators describe:
#   - Timing follows Fitts's law: the time to reach a target grows with log2(distance / target width + 1).
#   - Speed follows a minimum-jerk profile (Flash & Hogan 1985): slow start, fast middle, slow arrival.
#   - The route is a cubic Bezier whose two control points are on the SAME side of the straight line, as in ghost-cursor
#     (github.com/Xetera/ghost-cursor), so it bows gently one way instead of making an S.
#   - The wobble is correlated noise like WindMouse's "wind" (github.com/BenLand100's WindMouse, docs at
#     windmouse.readthedocs.io): each step's wind is the last one divided by sqrt(3) plus a small random kick, so the
#     pointer drifts smoothly instead of jittering, and it dies away near the target.
#   - A far target (over 500 px, ghost-cursor's overshootThreshold) is sometimes overshot by a few pixels and corrected.
#   - It lands a pixel or two off the exact point, and rests a moment before clicking.
#   - Typing intervals are log-normal, right-skewed with a floor near 60 ms, like the 136-million-keystroke study
#     (Dhakal et al., CHI 2018: mean 239 ms, SD 112, lower bound about 60 ms, skewness 2; fast typists about 120 ms), a little
#     quicker when the hands alternate and slower at the start of a word.
# TOUR_HUMAN=0 gives plain, even motion. TOUR_SEED=N makes the randomness repeatable. docs/recording-tours.md has the sources.
HUMAN=${TOUR_HUMAN:-1}
[[ -n ${TOUR_SEED:-} ]] && RANDOM=$TOUR_SEED
rnd() { awk -v lo="$1" -v hi="$2" -v s="$RANDOM$RANDOM" 'BEGIN { srand(s); printf "%.3f", lo + rand() * (hi - lo) }'; }

# path X0 Y0 X1 Y1: lines of "x y delay" from the first point to the second.
path() {
  awk -v x0="$1" -v y0="$2" -v x1="$3" -v y1="$4" -v seed="$RANDOM$RANDOM" 'BEGIN {
    srand(seed)
    dx = x1 - x0; dy = y1 - y0; d = sqrt(dx * dx + dy * dy)
    if (d < 2) { print x1, y1, 0.02; exit }
    ux = dx / d; uy = dy / d; nx = -uy; ny = ux
    # overshoot a far target by a few pixels, now and then, then settle back
    over = (d > 500 && rand() < 0.3) ? 2 + rand() * 3 : 0
    tx = x1 + ux * over; ty = y1 + uy * over
    # Fitts: movement time = a + b * log2(d / w + 1), with w about 40 px (a button) and a, b typical of a mouse
    mt = 0.15 + 0.12 * log(d / 40 + 1) / log(2)
    n = int(mt * 60); if (n < 12) n = 12; if (n > 60) n = 60
    # a cubic Bezier with both control points on one side of the line (kept small: at most about 10 px off the line)
    side = (rand() < 0.5) ? -1 : 1
    amp = (0.012 + rand() * 0.02) * d; if (amp > 16) amp = 16
    c1x = x0 + dx * 0.30 + nx * side * amp * (0.6 + rand() * 0.8); c1y = y0 + dy * 0.30 + ny * side * amp * (0.6 + rand() * 0.8)
    c2x = x0 + dx * 0.70 + nx * side * amp * (0.6 + rand() * 0.8); c2y = y0 + dy * 0.70 + ny * side * amp * (0.6 + rand() * 0.8)
    wx = 0; wy = 0
    r3 = sqrt(3); r5 = sqrt(5)
    for (i = 1; i <= n; i++) {
      t = i / n
      s = 10 * t^3 - 15 * t^4 + 6 * t^5          # minimum jerk
      u = 1 - s
      bx = u^3 * x0 + 3 * u^2 * s * c1x + 3 * u * s^2 * c2x + s^3 * tx
      by = u^3 * y0 + 3 * u^2 * s * c1y + 3 * u * s^2 * c2y + s^3 * ty
      # WindMouse-style wind: last wind / sqrt(3) plus a small kick, fading out towards the end
      wx = wx / r3 + (2 * rand() - 1) * 0.9 / r5; wy = wy / r3 + (2 * rand() - 1) * 0.9 / r5
      fade = (i < n) ? ((t < 0.9) ? 1 : (1 - t) / 0.1) : 0
      px = bx + wx * 2.2 * fade; py = by + wy * 2.2 * fade
      printf "%d %d %.3f\n", px + 0.5, py + 0.5, mt / n * (0.8 + 0.4 * rand())
    }
    if (over > 0) {
      for (k = 1; k <= 3; k++) {
        f = k / 3
        printf "%d %d %.3f\n", tx + (x1 - tx) * f + 0.5, ty + (y1 - ty) * f + 0.5, 0.04 + rand() * 0.05
      }
    }
  }'
}

glide() {
  lead_wait
  local x y dl
  if [[ $HUMAN != 1 ]]; then
    local i x0=$gx y0=$gy
    for i in 1 2 3 4 5 6 7 8; do at $((x0 + ($1 - x0) * i / 8)) $((y0 + ($2 - y0) * i / 8)); sleep 0.025; done
    return
  fi
  while read -r x y dl; do at "$x" "$y"; sleep "$dl"; done < <(path "$gx" "$gy" "$1" "$2")
  # Settles within a pixel or two of the exact point, as a hand does: a click uses where the pointer is.
  x=$(awk -v t="$1" -v s="$RANDOM$RANDOM" 'BEGIN { srand(s); printf "%d", t + int(rand() * 5) - 2 }')
  y=$(awk -v t="$2" -v s="$RANDOM$RANDOM" 'BEGIN { srand(s); printf "%d", t + int(rand() * 5) - 2 }')
  at "$x" "$y"
}
click() {
  glide "$1" "$2"
  if [[ $HUMAN == 1 ]]; then sleep "$(rnd 0.15 0.45)"; else sleep 0.35; fi
  # Clicks where the pointer is, which a person lands within a pixel or two of the target.
  if $NESTED; then nest_click "$gx" "$gy"; else ydotool click 0xC0 >/dev/null; fi
  sleep "${3:-0.9}"
}
drag() {
  lead_wait
  if $NESTED; then nest_drag "$1" "$2"; sleep 0.6; return; fi
  local i f px=0 py=0 nx ny
  ydotool click 0x40 >/dev/null; sleep "$([[ $HUMAN == 1 ]] && rnd 0.12 0.3 || echo 0.2)"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if [[ $HUMAN == 1 ]]; then
      f=$(awk -v i="$i" 'BEGIN { t = i / 10; printf "%.4f", t * t * (3 - 2 * t) }')
      nx=$(awk -v d="$1" -v f="$f" 'BEGIN { printf "%d", d * f }'); ny=$(awk -v d="$2" -v f="$f" 'BEGIN { printf "%d", d * f }')
      ydotool mousemove -x $((nx - px)) -y $((ny - py)) >/dev/null; px=$nx; py=$ny
      sleep "$(rnd 0.035 0.075)"
    else
      ydotool mousemove -x $(($1 / 10)) -y $(($2 / 10)) >/dev/null; sleep 0.05
    fi
  done
  sleep 0.2; ydotool click 0x80 >/dev/null; sleep 0.6
}
# Typing, a character at a time. Each gap is log-normal (right-skewed, never under about 60 ms), around 140 ms for a
# fairly fast typist; a little quicker when the next key is under the other hand and slower after a space, when a person
# is reading ahead (see the sources in docs/recording-tours.md).
type_chars() { # TEXT SENDER... : the sender is called with each character
  local text=$1 i c prev="" d
  shift
  for ((i = 0; i < ${#text}; i++)); do
    c=${text:i:1}
    "$@" "$c"
    d=$(awk -v c="$c" -v p="$prev" -v s="$RANDOM$RANDOM" 'BEGIN {
      srand(s)
      u1 = rand(); if (u1 < 1e-9) u1 = 1e-9; u2 = rand()
      z = sqrt(-2 * log(u1)) * cos(6.2831853 * u2)        # a normal draw
      d = 0.118 * exp(0.42 * z)                           # log-normal, median 118 ms, mean about 130 ms
      left = "qwertasdfgzxcvb12345"
      hc = (index(left, c) > 0) ? "L" : "R"; hp = (index(left, p) > 0) ? "L" : "R"
      if (p != "" && c != " " && p != " " && hc != hp) d *= 0.93      # the hands alternate: faster
      if (p != "" && c != " " && p != " " && hc == hp) d *= 1.06
      if (c == " ") d *= 1.35                                          # reading ahead at a word boundary
      if (d < 0.06) d = 0.06 + rand() * 0.01                          # about 60 ms is the floor
      if (d > 0.9) d = 0.9
      printf "%.3f", d
    }')
    sleep "$d"
    prev=$c
  done
}
_wtype_one() { WAYLAND_DISPLAY=$NWD wtype -- "$1"; }
_ydotool_one() { ydotool type -- "$1" >/dev/null; }
# Keys and typing only while the app's window is up on the virtual monitor: otherwise they would go to the
# backdrop window.
overlay_up() {
  [[ -n $TOUR_LAYER ]] || return 1
  hyprctl layers -j | jq -e --arg m "$CAPMON" --arg ns "$TOUR_LAYER" '.[$m] | [.. | .namespace? // empty] | any(. == $ns)' >/dev/null 2>&1
}
# key takes ydotool key codes (not in --nested mode: use esc and typed there).
key() {
  $NESTED && { echo "tour: key is not available with --nested, use esc or typed" >&2; return 1; }
  if overlay_up; then ydotool key "$@" >/dev/null; else echo "tour: window not up, skipped keys $*" >&2; fi
}
typed() {
  lead_wait
  if ! overlay_up; then echo "tour: window not up, skipped typing" >&2; return; fi
  if [[ $HUMAN == 1 ]]; then
    if $NESTED; then type_chars "$1" _wtype_one; else type_chars "$1" _ydotool_one; fi
  elif $NESTED; then nest_type "$1"
  else ydotool type --key-delay 45 "$1" >/dev/null
  fi
}
esc() {
  lead_wait
  if ! overlay_up; then echo "tour: window not up, skipped keys esc" >&2; return; fi
  if $NESTED; then nest_key Escape; else ydotool key 1:1 1:0 >/dev/null; fi
}
wait_until() { local i; for ((i = 0; i < ${2:-30} * 2; i++)); do eval "$1" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1; }

# ---- recording --------------------------------------------------------------------------------
caps="$TMP/captions.txt"
: >"$caps"
step=0
# Reading time. A caption has to stay up long enough to be read, and people read slowly when the picture is moving too.
# The average adult reads 238 words a minute (Brysbaert 2019, a meta-analysis of 190 studies; most adults 175 to 300),
# and subtitle standards run at about 160 to 180 words a minute (BBC) or 17 to 20 characters a second (Netflix). A caption
# is therefore held for 0.8 s to notice it (and 0.15 s of gap before the next one) plus its words at TOUR_READ_WPM (default
# 150, slower than all of those), and never under 2.5 s. TOUR_READ_WPM=0 turns the minimum off. The tour waits out what is missing before the next caption.
READ_WPM=${TOUR_READ_WPM:-150}
cap_t0=""
cap_hold=0
cap_say=""
hold_wait() { # waits until the current caption has been up long enough to read
  [[ -n $cap_t0 ]] || return 0
  local left
  left=$(awk -v t0="$cap_t0" -v hold="$cap_hold" -v now="$(date +%s.%N)" 'BEGIN { l = t0 + hold - now; printf "%.2f", (l > 0) ? l : 0 }')
  awk -v l="$left" 'BEGIN { exit !(l > 0) }' && sleep "$left"
  return 0
}
# The reading lead. A viewer reads a new caption before looking at what the pointer does, so the first pointer or key action
# after a caption waits for the time an average adult needs to read it: 0.5 s to notice it plus its words at TOUR_LEAD_WPM
# (default 238, the Brysbaert average), a little different each time. Opening a window is not input, so it appears with the
# caption and there is something to look at while reading. TOUR_LEAD_WPM=0 turns the lead off.
LEAD_WPM=${TOUR_LEAD_WPM:-238}
lead_until=""
lead_wait() {
  [[ -n $lead_until ]] || return 0
  local left
  left=$(awk -v u="$lead_until" -v now="$(date +%s.%N)" 'BEGIN { l = u - now; printf "%.2f", (l > 0) ? l : 0 }')
  awk -v l="$left" 'BEGIN { exit !(l > 0) }' && sleep "$left"
  lead_until=""
  return 0
}
cap() {
  hold_wait
  step=$((step + 1))
  printf '%s|%s\n' "$(date +%s%N)" "$1" >>"$caps"
  say "Step $step${TOUR_STEPS:+ of $TOUR_STEPS}: $1"
  cap_t0=$(date +%s.%N)
  cap_say=$1
  lead_until=$(awk -v t0="$cap_t0" -v w="$(wc -w <<<"$1")" -v wpm="$LEAD_WPM" -v s="$RANDOM$RANDOM" 'BEGIN { if (wpm <= 0) { print ""; exit } srand(s); printf "%.2f", t0 + (0.5 + w * 60 / wpm) * (0.9 + rand() * 0.3) }')
  cap_hold=$(awk -v w="$(wc -w <<<"$1")" -v wpm="$READ_WPM" 'BEGIN { if (wpm <= 0) { print 0; exit } h = 0.95 + w * 60 / wpm; if (h < 2.5) h = 2.5; printf "%.2f", h }')
}

(while :; do grim -c -t jpeg -q 90 -o "$CAPMON" "$TMP/frames/$(date +%s%N).jpg"; done) &
rec_pid=$!
sleep 0.6
say "Starting the tour"
tour_play
hold_wait
kill "$rec_pid" 2>/dev/null; wait "$rec_pid" 2>/dev/null
rec_pid=""
# Filming is over: give the screen, mouse and keyboard back now, and say that the GIF is being built.
release
say encoding "Building the GIF..."

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
  words=$(wc -w <<<"$text")
  echo "tour: caption $i ($words words) on screen $(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.1f", b - a }') s (reading time $(awk -v w="$words" -v wpm="$READ_WPM" 'BEGIN { h = 0.95 + w * 60 / wpm; if (h < 2.5) h = 2.5; printf "%.1f", h }') s)" >&2
  vf+="drawtext=fontfile=$TOUR_FONT:text='$text':fontsize=24:fontcolor=white:box=1:boxcolor=0x13151f@0.88:boxborderw=14:x=(w-text_w)/2:y=h-70:enable='between(t,$start,$end)',"
done <"$caps"
printf '%s' "$vf" >"$TMP/vf.txt"

# The result is an AVIF or a GIF, by the extension of TOUR_OUT (a tour file sets it; the default is screenshots/hero.avif).
# An animated AVIF holds the same 79 seconds in under half a megabyte where a GIF takes over three, so AVIF is the
# default for the README; browsers show it in an <img>, and GitHub serves it as image/avif.
#   AVIF: TOUR_AVIF_CRF sets the quality (lower is sharper and bigger; 40 by default, 32 is crisper, 24 sharper still)
#   GIF:  TOUR_GIF_COLORS sets the palette (128 by default)
#   both: TOUR_GIF_WIDTH sets the width in pixels (1000 by default)
width=${TOUR_GIF_WIDTH:-1000}
case ${TOUR_OUT##*.} in
  avif)
    ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libaom-av1 || { echo "tour: ffmpeg has no libaom-av1 encoder, which an .avif needs" >&2; exit 1; }
    ffmpeg -loglevel error -y -ss 0.4 -i "$TMP/tour.mp4" \
      -vf "${vf}fps=10,scale=${width}:-1:flags=lanczos,format=yuv420p" \
      -c:v libaom-av1 -crf "${TOUR_AVIF_CRF:-40}" -b:v 0 -cpu-used 6 -f avif "$TMP/result" ;;
  *)
    ffmpeg -loglevel error -y -ss 0.4 -i "$TMP/tour.mp4" \
      -vf "${vf}fps=10,scale=${width}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${TOUR_GIF_COLORS:-128}:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
      -loop 0 -f gif "$TMP/result" ;;
esac
echo "tour: ${TOUR_OUT##*.} $(du -h "$TMP/result" | cut -f1)"

if $install; then
  mkdir -p "$(dirname "$REPO/$TOUR_OUT")"
  cp "$TMP/result" "$REPO/$TOUR_OUT"
  echo "tour: wrote $REPO/$TOUR_OUT"
else
  keep=${TMPDIR:-/tmp}/$(basename "$TOUR_OUT")
  cp "$TMP/result" "$keep"
  echo "tour: look at $keep, then run again with --install"
fi
