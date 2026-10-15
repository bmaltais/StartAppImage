# shellcheck shell=bash
# The nested session for the tour recorder (scripts/tour.sh --nested), sourced by it.
#
# Instead of filming a hidden virtual monitor and driving your real mouse and keyboard, the tour runs inside a
# second Hyprland that opens as a window on your screen. In it runs a second Omarchy shell with only the app's
# plugin, in a sandbox home that holds copies of the app's data. So:
#   - you can watch it, in a window;
#   - your mouse and keyboard cannot reach it (a transparent shield covers the window, and it is never focused);
#   - the tour is driven over that session's own Wayland socket (a virtual pointer and virtual keyboard), so
#     nothing the tour does moves your pointer or types into your windows;
#   - the tour changes only the sandbox: your real settings, apps and files are not touched, so there is nothing
#     to put back.
# Needs: Hyprland, dbus-run-session, wtype, gcc and wayland-scanner (to build the pointer client, once per run).
# docs/recording-tours.md "Nested mode" says how it works.

NEST=$TMP/nest
NEST_HOME=$NEST/home
NEST_BIN=$NEST/bin
NEST_RT=${XDG_RUNTIME_DIR:-/run/user/$UID}
REAL_SIG=${HYPRLAND_INSTANCE_SIGNATURE:-}
REAL_WD=${WAYLAND_DISPLAY:-}
nest_pid=""
NSIG=""
NWD=""
NMON=""
NW=0
NH=0
VPTR=$NEST_BIN/vptr
# The status strip (scripts/tour-banner.qml) sits NEST_STRIP_GAP pixels from the top of the monitor and is NEST_STRIP_H high;
# the nested window goes below it, clear of the strip and of its own title bar (NEST_TITLEBAR, which Hyprland draws above
# the window's position). They are worked out from these, never typed twice, so they cannot drift apart.
NEST_STRIP_GAP=24
NEST_STRIP_H=170
NEST_TITLEBAR=30
NEST_BELOW=10
NEST_TOP=$((NEST_STRIP_GAP + NEST_STRIP_H + NEST_BELOW + NEST_TITLEBAR))

real() { env HYPRLAND_INSTANCE_SIGNATURE="$REAL_SIG" WAYLAND_DISPLAY="$REAL_WD" "$@"; }

nested_requires() {
  local tool
  for tool in Hyprland dbus-run-session wtype gcc wayland-scanner pkg-config; do
    command -v "$tool" >/dev/null || { echo "tour: --nested needs $tool" >&2; return 1; }
  done
  [[ -n $REAL_SIG && -n $REAL_WD ]] || { echo "tour: --nested must run inside your Hyprland session" >&2; return 1; }
  [[ -n ${TOUR_PLUGIN_ID:-} ]] || { echo "tour: --nested needs TOUR_PLUGIN_ID in the tour file (the plugin to load in the sandbox)" >&2; return 1; }
}

# A home of its own for the nested session: the Omarchy themes it needs, a minimal shell config that loads only
# the app's plugin (linked to this checkout, so the tour shows the code you are working on), and copies of the
# data the tour file lists. Nothing here points back at your real files except read-only links.
sandbox_build() {
  local h=$NEST_HOME rel
  mkdir -p "$h/.config/omarchy/plugins" "$h/.local/share" "$h/.local/state/omarchy" "$h/.cache" "$NEST_BIN"
  for rel in branding defaults extensions hooks themed themes; do
    [[ -e $HOME/.config/omarchy/$rel ]] && cp -a "$HOME/.config/omarchy/$rel" "$h/.config/omarchy/"
  done
  [[ -e $HOME/.local/state/omarchy/current ]] && ln -s "$HOME/.local/state/omarchy/current" "$h/.local/state/omarchy/current"
  ln -s "$REPO" "$h/.config/omarchy/plugins/$TOUR_PLUGIN_ID"
  # The bar is your real one, so it looks like your desktop: its settings, and the layout kept to Omarchy's own widgets
  # (other plugins are left out: they would start their own services) plus this app.
  local real_cfg=$HOME/.config/omarchy/shell.json
  [[ -s $real_cfg ]] || real_cfg=${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json
  jq --arg id "$TOUR_PLUGIN_ID" '
      def own: map(select((if type == "object" then .id else . end) as $i | ($i | tostring | startswith("omarchy.")) or $i == $id));
      {version: 1, bar: ((.bar // {}) | .layout |= (. // {} | with_entries(.value |= (if type == "array" then own else . end)))),
       plugins: [{id: $id}]}
      | if ([.bar.layout[]?[]? | (if type == "object" then .id else . end)] | index($id)) == null
        then .bar.layout.right += [{id: $id}] else . end' "$real_cfg" >"$h/.config/omarchy/shell.json" ||
    jq -n --arg id "$TOUR_PLUGIN_ID" '{version: 1, bar: {layout: {left: [{id: "omarchy.menu"}], center: [{id: "omarchy.clock"}], right: [{id: $id}]}}, plugins: [{id: $id}]}' >"$h/.config/omarchy/shell.json"
  for rel in "${TOUR_SANDBOX_COPY[@]:-}"; do
    [[ -n $rel && -e $HOME/$rel ]] || continue
    mkdir -p "$h/$(dirname "$rel")"
    cp -a "$HOME/$rel" "$h/$rel"
  done
  for rel in "${TOUR_SANDBOX_LINK[@]:-}"; do
    [[ -n $rel && -e $HOME/$rel ]] || continue
    mkdir -p "$h/$(dirname "$rel")"
    ln -s "$HOME/$rel" "$h/$rel"
  done
  if declare -F tour_sandbox >/dev/null; then tour_sandbox "$h"; fi
  "$HERE/nested/build.sh" "$NEST_BIN" >/dev/null || { echo "tour: could not build the virtual pointer client" >&2; return 1; }
}

# From here on every command the tour runs, and the recorder's own helpers, act in the sandbox.
sandbox_enter() {
  export HOME=$NEST_HOME XDG_CONFIG_HOME=$NEST_HOME/.config XDG_DATA_HOME=$NEST_HOME/.local/share \
    XDG_STATE_HOME=$NEST_HOME/.local/state XDG_CACHE_HOME=$NEST_HOME/.cache
}

nested_start() {
  local before_sigs before_socks before_wins sig sock i addr
  before_sigs=$(ls "$NEST_RT/hypr" 2>/dev/null)
  before_socks=$(ls "$NEST_RT" 2>/dev/null | grep -E '^wayland-[0-9]+$')
  before_wins=$(real hyprctl clients -j | jq -r '.[].address')
  cat >"$NEST/hypr.lua" <<'LUA'
-- A bare nested session for the tour recorder. None of Omarchy's own autostart: it would push this session's
-- environment into your real one.
hl.config({
  general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0, disable_watchdog_warning = true },
  animations = { enabled = false },
})
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.on("hyprland.start", function()
  hl.exec_cmd("QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 quickshell -n -p " .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/shell")
end)
LUA
  # Its own D-Bus, and one that starts nothing by itself: the usual one launches portals, file services and
  # accessibility daemons that this session does not need, and a portal that has no real display crashes.
  mkdir -p "$NEST/dbus-services"
  cat >"$NEST/dbus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
  <servicedir>$NEST/dbus-services</servicedir>
</busconfig>
CONF
  env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD dbus-run-session --config-file="$NEST/dbus.conf" -- Hyprland -c "$NEST/hypr.lua" >"$NEST/hypr.log" 2>&1 &
  nest_pid=$!
  for i in $(seq 1 60); do
    sig=$(comm -13 <(echo "$before_sigs" | sort) <(ls "$NEST_RT/hypr" 2>/dev/null | sort) | head -n1)
    sock=$(comm -13 <(echo "$before_socks" | sort) <(ls "$NEST_RT" 2>/dev/null | grep -E '^wayland-[0-9]+$' | sort) | head -n1)
    [[ -n $sig && -n $sock ]] && break
    sleep 0.5
  done
  [[ -n $sig && -n $sock ]] || { echo "tour: the nested session did not start (see $NEST/hypr.log)" >&2; return 1; }
  NSIG=$sig
  NWD=$sock
  # Its window on the real screen: found by being new, then sized, placed and left unfocused.
  for i in $(seq 1 30); do
    addr=$(comm -13 <(echo "$before_wins" | sort) <(real hyprctl clients -j | jq -r '.[].address' | sort) | head -n1)
    [[ -n $addr ]] && break
    sleep 0.3
  done
  [[ -n $addr ]] || { echo "tour: the nested session's window did not appear" >&2; return 1; }
  NEST_ADDR=$addr
}

# Size and place the window, and hand the real keyboard back to what had it.
nested_place() { # PREVIOUS_FOCUS_ADDRESS
  local mx my mw
  local mh
  read -r mx my mw mh < <(real hyprctl monitors -j | jq -r --arg m "$orig_mon" '.[] | select(.name == $m) | "\(.x) \(.y) \(.width) \(.height)"')
  if (( mh < NEST_TOP + H + 8 )); then
    echo "tour: the monitor is ${mh}px high; the nested window (${H}px) plus its status strip needs $((NEST_TOP + H + 8))px. They will overlap by $((NEST_TOP + H + 8 - mh))px at the bottom." >&2
  fi
  real hyprctl dispatch "hl.dsp.window.resize({ x = $W, y = $H, exact = true, window = \"address:$NEST_ADDR\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.move({ x = $((mx + (mw - W) / 2)), y = $((my + NEST_TOP)), exact = true, window = \"address:$NEST_ADDR\" })" >/dev/null
  SHIELD="$(((mw - W) / 2)),$NEST_TOP,$W,$H"
  [[ -n ${1:-} ]] && real hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null
  # Handing the keyboard back raised that window over this one: put this one on top again, and keep it there.
  real hyprctl dispatch "hl.dsp.window.alter_zorder({ mode = \"top\", window = \"address:$NEST_ADDR\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.pin({ action = \"enable\", window = \"address:$NEST_ADDR\" })" >/dev/null
  sleep 1
}

nested_wait_ready() {
  local i
  for i in $(seq 1 60); do
    if env WAYLAND_DISPLAY="$NWD" HYPRLAND_INSTANCE_SIGNATURE="$NSIG" omarchy-shell shell ping >/dev/null 2>&1; then break; fi
    sleep 0.5
  done
  NMON=$(env HYPRLAND_INSTANCE_SIGNATURE=$NSIG hyprctl monitors -j | jq -r '.[0].name')
  read -r NW NH < <(env HYPRLAND_INSTANCE_SIGNATURE=$NSIG hyprctl monitors -j | jq -r '.[0] | "\(.width) \(.height)"')
  echo "tour: nested session $NSIG on $NWD, $NMON ${NW}x${NH}" >&2
}

# From here on `hyprctl`, `omarchy-shell` and friends act on the nested session.
nested_enter() { export WAYLAND_DISPLAY=$NWD HYPRLAND_INSTANCE_SIGNATURE=$NSIG; }

# Calls "$1 PID COMMAND" for each process that carries the sandbox's XDG_CONFIG_HOME: everything the nested session
# started (its compositor, shell, its own D-Bus, portals, file watchers). Mine alone: the check is the sandbox's path.
nested_procs() {
  local p comm
  for p in /proc/[0-9]*; do
    p=${p#/proc/}
    [[ $p != "$$" && -r /proc/$p/environ ]] || continue
    if tr '\0' '\n' </proc/"$p"/environ 2>/dev/null | grep -qx "XDG_CONFIG_HOME=$NEST_HOME/.config"; then
      comm=$(cat /proc/"$p"/comm 2>/dev/null)
      "$1" "$p" "$comm"
    fi
  done 2>/dev/null
}
_nested_term() { [[ $2 == Hyprland ]] || kill -TERM "$1" 2>/dev/null; }
_nested_kill() { kill -KILL "$1" 2>/dev/null; }

nested_stop() {
  [[ -n $nest_pid ]] || return 0
  # What runs inside goes first, then the compositor: a portal that loses its compositor crashes, and Omarchy tells you.
  nested_procs _nested_term
  sleep 1.5
  env HYPRLAND_INSTANCE_SIGNATURE="$NSIG" hyprctl dispatch "hl.dsp.exit()" >/dev/null 2>&1
  sleep 1.5
  kill "$nest_pid" 2>/dev/null
  nest_pid=""
  nested_procs _nested_kill
}

# ---- input: over the nested session's own socket --------------------------------------------------------
nest_at() { WAYLAND_DISPLAY=$NWD "$VPTR" move "$1" "$2" "$NW" "$NH"; }
nest_click() { WAYLAND_DISPLAY=$NWD "$VPTR" click "$1" "$2" "$NW" "$NH"; }
nest_drag() { WAYLAND_DISPLAY=$NWD "$VPTR" drag "$gx" "$gy" "$NW" "$NH" "$1" "$2"; gx=$((gx + $1)); gy=$((gy + $2)); }
nest_type() { WAYLAND_DISPLAY=$NWD wtype -d 45 -- "$1"; }
nest_key() { WAYLAND_DISPLAY=$NWD wtype -k "$1"; }
