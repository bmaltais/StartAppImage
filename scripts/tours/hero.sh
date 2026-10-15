# shellcheck shell=bash
# StartAppImage's tour: the GIF at the top of the README (screenshots/hero.gif).
# Run it with scripts/tour.sh scripts/tours/hero.sh --install (or scripts/hero.sh --install).
#
# The story: double-click an AppImage and see what it is; the manager with an update waiting; one click
# to update; point an app at its GitHub releases; settings that apply at once (the check interval, the bar
# icon, search); resize and move the window and find it where it was left.
#
# What it changes while it runs, and puts back: the manager's and the settings window's saved size and place
# (reset to the defaults, so the shell is restarted), ArtCraft Launcher looking one version behind (the update
# then downloads the real release, 12 MB, to the same file), the update check interval and the bar icon.
# Needs the apps it uses installed in StartAppImage: ArtCraft Launcher (with a GitHub source) and PdfCraft.

TOUR_TITLE=StartAppImage
TOUR_OUT=screenshots/hero.gif
TOUR_LAYER=omarchy-startappimage
TOUR_STEPS=6
TOUR_RESTART_SHELL=1

ID=io.github.bmaltais.startappimage
CLI=$HOME/.config/omarchy/plugins/$ID/bin/startappimage
ARTENV=$HOME/.local/share/startappimage/artcraft-launcher.env
APPIMG=$(ls "$HOME"/Applications/pdfcraft-*.AppImage 2>/dev/null | head -n1)

tour_requires() {
  [[ -x $CLI ]] || { echo "tour: the plugin is not installed at $CLI" >&2; return 1; }
  [[ -f $ARTENV ]] || { echo "tour: ArtCraft Launcher is not installed from StartAppImage" >&2; return 1; }
  [[ -n $APPIMG ]] || { echo "tour: no ~/Applications/pdfcraft-*.AppImage to open" >&2; return 1; }
}

tour_prepare() {
  orig_win=$("$CLI" window)
  orig_info=$("$CLI" integration)
  cp "$ARTENV" "$TMP/artcraft.env"
  # Both windows start where the defaults put them, and the shell picks that up on a restart.
  "$CLI" window --reset >/dev/null
  "$CLI" window --reset-setup >/dev/null
}

tour_setup() {
  # ArtCraft looks one version behind, so the tour has something to update.
  sed -i 's/^VERSION=.*/VERSION=v0.4.0/' "$ARTENV"
}

tour_restore() {
  omarchy-shell -q $ID close 2>/dev/null
  cp "$TMP/artcraft.env" "$ARTENV"
  "$CLI" setup --bar-icon "$(jq -r .barIcon <<<"$orig_info")" --check-hours "$(jq -r .checkHours <<<"$orig_info")" >/dev/null 2>&1
  "$CLI" window --size "$(jq -r '"\(.w)x\(.h)"' <<<"$orig_win")" --offset "$(jq -r '"\(.x),\(.y)"' <<<"$orig_win")" \
    --setup-size "$(jq -r '"\(.setup.w)x\(.setup.h)"' <<<"$orig_win")" --setup-offset "$(jq -r '"\(.setup.x),\(.setup.y)"' <<<"$orig_win")" >/dev/null 2>&1
  "$CLI" check >/dev/null 2>&1
}

tour_play() {
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
  wait_until "grep -q '^VERSION=v0.4.1' '$ARTENV'" 30
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
  esc; sleep 0.35
}
