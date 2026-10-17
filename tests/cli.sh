#!/usr/bin/env bash
# Behaviour tests for bin/startappimage, run through its command line against a throwaway $HOME.
# Nothing here touches the real home, the network or the desktop. A test is a function named t_*.
#
#   tests/cli.sh              all tests
#   tests/cli.sh add remove   only tests whose name contains one of the words
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/startappimage"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# --- harness ------------------------------------------------------------------
PASS=0 FAIL=0 FAILED_NOW=0
OUT="" ERR="" CODE=0

fail() { printf '        %s\n' "$*"; FAILED_NOW=1; }
eq() { [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"; }
has() { [[ $1 == *"$2"* ]] || fail "${3:-output}: expected to contain [$2], got [$1]"; }
exists() { [[ -e $1 || -L $1 ]] || fail "expected to exist: ${1#"$HOME"/}"; }
absent() { [[ ! -e $1 && ! -L $1 ]] || fail "expected to be gone: ${1#"$HOME"/}"; }
ok() { [[ $CODE -eq 0 ]] || fail "expected success, exit $CODE: $ERR"; }
refused() { [[ $CODE -ne 0 ]] || fail "expected a failure, got success: $OUT"; has "$ERR" "$1" "error message"; }
jqv() { jq -r "$1" <<<"$OUT"; } # a value of the last command's JSON output

# cli ARGS...: run the command line in the fixture home; sets OUT ERR CODE.
cli() {
  local e="$SCRATCH/err"
  OUT=$(bash "$CLI" "$@" 2>"$e"); CODE=$?
  ERR=$(<"$e")
}

# Each test gets a home of its own, with the XDG variables of the real session unset.
fresh_home() {
  HOME=$(mktemp -d -p "$SCRATCH")
  export HOME
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME STARTAPPIMAGE_DIR
  mkdir -p "$HOME/Downloads"
}

# fake_appimage FILE NAME VERSION [ICON-EXT|link:TARGET]: an ELF header stub followed by a real squashfs, so it is read
# like an AppImage but cannot be run (it would fail to execute, which proves nothing ran it).
fake_appimage() {
  local src sq ext=${4:-png}
  src=$(mktemp -d -p "$SCRATCH"); sq="$src.sq"
  printf '[Desktop Entry]\nName=%s\nComment=A demo\nCategories=Graphics;\nX-AppImage-Version=%s\nIcon=demo\nExec=demo\n' "$2" "$3" >"$src/demo.desktop"
  if [[ $ext == link:* ]]; then ln -s "${ext#link:}" "$src/demo.png"
  elif [[ $ext == svg ]]; then printf '<svg/>' >"$src/demo.svg"; else printf 'png' >"$src/demo.png"; fi
  mksquashfs "$src" "$sq" -noappend -quiet >/dev/null
  { printf '\177ELF'; head -c 36 /dev/zero; printf '\100\0\0\0\0\0\0\0'; head -c 10 /dev/zero; printf '\100\0'; head -c 4 /dev/zero; cat "$sq"; } >"$1"
  chmod +x "$1"
}

# install_demo: install "Demo App" 1.2 from a local file; sets $APPS to the default install folder.
install_demo() {
  fake_appimage "$HOME/Downloads/Demo.AppImage" "Demo App" 1.2
  cli add "$HOME/Downloads/Demo.AppImage"
  APPS="$HOME/.local/share/appimages"
}

# --- add / list / config ------------------------------------------------------
t_add_installs_the_app_and_its_integration() {
  install_demo; ok
  has "$OUT" "Installed Demo App (demo-app)" "add output"
  exists "$APPS/demo-app.AppImage"
  eq "$(readlink "$HOME/.local/bin/demo-app")" "$APPS/demo-app.AppImage" "bin link"
  exists "$HOME/.local/share/icons/hicolor/256x256/apps/startappimage-demo-app.png"
  local d="$HOME/.local/share/applications/startappimage-demo-app.desktop"
  exists "$d"
  has "$(<"$d")" "Name=Demo App" "launcher entry"
  has "$(<"$d")" "Exec=\"$APPS/demo-app.AppImage\" %U" "launcher entry"
  has "$(<"$d")" "Icon=startappimage-demo-app" "launcher entry"
  has "$(<"$HOME/.local/share/startappimage/demo-app.env")" "VERSION=1.2" "manifest"
}

t_add_without_a_source_fails() {
  cli add; refused "add: missing source"
}

t_add_a_missing_file_fails() {
  cli add "$HOME/nope.AppImage"; refused "no such file"
}

t_add_outside_home_fails() {
  fake_appimage "$HOME/Downloads/Demo.AppImage" "Demo App" 1.2
  cli add "$HOME/Downloads/Demo.AppImage" --dir /opt/apps; refused "inside your home directory"
  cli add "$HOME/Downloads/Demo.AppImage" --dir /opt/apps --json; eq "$(jqv '.field')" dir "field"
}

t_add_with_a_name_overrides_the_app_name() {
  fake_appimage "$HOME/Downloads/Demo.AppImage" "Demo App" 1.2
  cli add "$HOME/Downloads/Demo.AppImage" "My Demo"; ok
  has "$OUT" "(my-demo)" "add output"
  exists "$HOME/.local/share/appimages/my-demo.AppImage"
}

t_add_with_a_dir_remembers_it_for_next_time() {
  fake_appimage "$HOME/Downloads/Demo.AppImage" "Demo App" 1.2
  cli add "$HOME/Downloads/Demo.AppImage" --dir "$HOME/Apps"; ok
  exists "$HOME/Apps/demo-app.AppImage"
  has "$(<"$HOME/.config/startappimage/config")" "INSTALL_DIR=$HOME/Apps" "config"
  fake_appimage "$HOME/Downloads/Other.AppImage" "Other" 3
  cli add "$HOME/Downloads/Other.AppImage"; ok
  exists "$HOME/Apps/other.AppImage"
}

t_adding_again_into_another_folder_moves_the_app() {
  install_demo
  cli add "$HOME/Downloads/Demo.AppImage" --dir "$HOME/Apps"; ok
  absent "$APPS/demo-app.AppImage"
  exists "$HOME/Apps/demo-app.AppImage"
  eq "$(readlink "$HOME/.local/bin/demo-app")" "$HOME/Apps/demo-app.AppImage" "bin link"
  cli list --json; eq "$(jqv 'length')" 1 "apps listed"
}

t_list_json_describes_each_app() {
  install_demo
  cli list --json; ok
  eq "$(jqv '.[0].id')" demo-app "id"
  eq "$(jqv '.[0].name')" "Demo App" "name"
  eq "$(jqv '.[0].version')" 1.2 "version"
  eq "$(jqv '.[0].source')" local "source"
  eq "$(jqv '.[0].external')" false "external"
  eq "$(jqv '.[0].exec')" "$APPS/demo-app.AppImage" "exec"
  exists "$(jqv '.[0].icon')"
}

t_list_json_of_nothing_is_an_empty_array() {
  cli list --json; ok; eq "$(jqv 'length')" 0 "apps listed"
}

t_list_prints_a_line_per_app() {
  install_demo
  cli list; ok; has "$OUT" "demo-app" "list"; has "$OUT" "1.2" "list"
}

t_config_reports_one_app() {
  install_demo
  cli config "Demo App"; ok
  eq "$(jqv '.id')" demo-app "id"
  eq "$(jqv '.dir')" "$APPS" "dir"
  eq "$(jqv '.args')" "" "args"
  eq "$(jqv '.hidden')" false "hidden"
}

t_config_of_an_unknown_app_fails() {
  cli config nothing; refused "not installed: nothing"
}

t_add_json_reports_the_installed_app_as_one_json_line() {
  fake_appimage "$HOME/Downloads/Demo.AppImage" "Demo App" 1.2
  cli add "$HOME/Downloads/Demo.AppImage" --json; ok
  eq "$(wc -l <<<"$OUT")" 1 "stdout lines"
  eq "$(jqv '.ok')" true "ok"
  eq "$(jqv '.id')" demo-app "id"
  eq "$(jqv '.name')" "Demo App" "name"
  has "$ERR" "Installing to" "progress is on stderr"
}

t_add_json_reports_a_failure_as_json_too() {
  cli add "$HOME/nope.AppImage" --json; [[ $CODE -ne 0 ]] || fail "expected a failure"
  eq "$(jqv '.ok')" false "ok"
  has "$(jqv '.error')" "no such file" "error"
  eq "$ERR" "" "stderr"
}

t_list_and_config_say_what_the_source_is() {
  install_demo
  cli list --json; eq "$(jqv '.[0].sourceKind')" local "kind"; eq "$(jqv '.[0].repo')" "" "repo"
  cli set demo-app --source foo/bar; ok
  cli list --json; eq "$(jqv '.[0].sourceKind')" github "kind"; eq "$(jqv '.[0].repo')" foo/bar "repo"
  cli config demo-app; eq "$(jqv '.sourceKind')" github "kind"; eq "$(jqv '.repo')" foo/bar "repo"
}

t_an_adopted_app_has_the_external_source_kind() {
  adopt_demo
  cli list --json; eq "$(jqv '.[0].sourceKind')" external "kind"
}

# --- set ----------------------------------------------------------------------
t_set_changes_name_args_and_hidden() {
  install_demo
  cli set demo-app --name "Renamed" --args "--flag one" --hidden true; ok
  has "$OUT" "Saved demo-app" "set output"
  cli config demo-app
  eq "$(jqv '.name')" Renamed "name"
  eq "$(jqv '.args')" "--flag one" "args"
  eq "$(jqv '.hidden')" true "hidden"
  has "$(<"$HOME/.local/share/applications/startappimage-demo-app.desktop")" "Exec=\"$APPS/demo-app.AppImage\" --flag one %U" "Exec"
  cli set demo-app --hidden false; ok
  cli config demo-app; eq "$(jqv '.hidden')" false "hidden"
}

t_set_source_accepts_a_github_link_or_clears_it() {
  install_demo
  cli set demo-app --source "https://github.com/foo/bar/releases"; ok
  cli config demo-app; eq "$(jqv '.source')" "github:foo/bar" "source"
  cli set demo-app --source ""; ok
  cli config demo-app; eq "$(jqv '.source')" local "source"
}

t_set_source_that_is_not_a_repo_fails() {
  install_demo
  cli set demo-app --source "not a repo"; refused "owner/repo"
}

t_set_dir_moves_the_app_and_keeps_the_link() {
  install_demo
  cli set demo-app --dir "$HOME/Apps"; ok
  absent "$APPS/demo-app.AppImage"
  exists "$HOME/Apps/demo-app.AppImage"
  eq "$(readlink "$HOME/.local/bin/demo-app")" "$HOME/Apps/demo-app.AppImage" "bin link"
  cli config demo-app; eq "$(jqv '.dir')" "$HOME/Apps" "dir"
  has "$(<"$HOME/.local/share/applications/startappimage-demo-app.desktop")" "Exec=\"$HOME/Apps/demo-app.AppImage\"" "Exec"
}

t_set_dir_outside_home_fails() {
  install_demo
  cli set demo-app --dir /opt; refused "inside your home directory"
}

t_set_json_confirms_a_change() {
  install_demo
  cli set demo-app --name Renamed --json; ok
  eq "$(jqv '.ok')" true "ok"; eq "$(jqv '.id')" demo-app "id"
}

t_set_json_applies_every_option_like_plain_set() {
  install_demo
  cli set demo-app --hidden true --json; ok
  cli config demo-app; eq "$(jqv '.hidden')" true "hidden"
}

t_set_json_names_the_field_a_failure_belongs_to() {
  install_demo
  cli set demo-app --source "not a repo" --json; [[ $CODE -ne 0 ]] || fail "expected a failure"
  eq "$(jqv '.ok')" false "ok"; eq "$(jqv '.field')" source "field"
  has "$(jqv '.error')" "owner/repo" "error"
  cli set demo-app --dir /opt --json; eq "$(jqv '.field')" dir "field"
  cli set nothing --name X --json; eq "$(jqv '.field')" "" "field of a general failure"
  has "$(jqv '.error')" "not installed" "error"
}

t_set_hidden_takes_true_or_false() {
  install_demo
  cli set demo-app --hidden maybe; refused "true or false"
}

t_set_of_an_unknown_app_fails() {
  cli set nothing --name X; refused "not installed: nothing"
}

# --- folder -------------------------------------------------------------------
t_folder_accepts_a_path_inside_home_and_expands_it() {
  # shellcheck disable=SC2088 # the CLI is what expands the tilde
  cli folder '~/Tools/Apps/'; ok
  eq "$(jqv '.ok')" true "ok"; eq "$(jqv '.path')" "$HOME/Tools/Apps" "path"
}

t_folder_refuses_a_path_outside_home() {
  cli folder /opt/apps; ok
  eq "$(jqv '.ok')" false "ok"; has "$(jqv '.error')" "inside your home" "error"
  cli folder "$HOME"; eq "$(jqv '.ok')" false "home itself is not a folder to install into"
}

# --- remove -------------------------------------------------------------------
t_remove_deletes_every_file_the_install_made() {
  install_demo
  cli remove "Demo App"; ok
  has "$OUT" "Removed demo-app" "remove output"
  absent "$APPS/demo-app.AppImage"
  absent "$HOME/.local/bin/demo-app"
  absent "$HOME/.local/share/applications/startappimage-demo-app.desktop"
  absent "$HOME/.local/share/icons/hicolor/256x256/apps/startappimage-demo-app.png"
  absent "$HOME/.local/share/startappimage/demo-app.env"
  cli list --json; eq "$(jqv 'length')" 0 "apps listed"
}

t_remove_json_confirms_and_names_a_failure() {
  install_demo
  cli remove demo-app --json; ok; eq "$(jqv '.ok')" true "ok"; eq "$(jqv '.id')" demo-app "id"
  cli remove demo-app --json; [[ $CODE -ne 0 ]] || fail "expected a failure"
  eq "$(jqv '.ok')" false "ok"; has "$(jqv '.error')" "not installed" "error"
}

t_remove_an_unknown_app_fails() {
  cli remove nothing; refused "not installed: nothing"
}

t_an_svg_icon_is_installed_listed_and_removed_with_the_app() {
  fake_appimage "$HOME/Downloads/Vec.AppImage" "Vec" 1 svg
  cli add "$HOME/Downloads/Vec.AppImage"; ok
  local svg="$HOME/.local/share/icons/hicolor/scalable/apps/startappimage-vec.svg"
  exists "$svg"
  cli list --json; eq "$(jqv '.[0].icon')" "$svg" "icon"
  cli remove vec; ok
  absent "$svg"
}

# --- adopted apps -------------------------------------------------------------
adopt_demo() { # a launcher entry the user made by hand, pointing at an AppImage in ~/Applications
  mkdir -p "$HOME/Applications" "$HOME/.local/share/applications"
  fake_appimage "$HOME/Applications/Hand-2.0.AppImage" "Hand Made" 2.0
  printf '[Desktop Entry]\nType=Application\nName=Hand Made\nExec=%s %%U\nIcon=hand\n' "$HOME/Applications/Hand-2.0.AppImage" \
    >"$HOME/.local/share/applications/hand.desktop"
}

t_a_hand_made_launcher_entry_is_adopted() {
  adopt_demo
  cli list --json; ok
  eq "$(jqv '.[0].id')" hand-made "id"
  eq "$(jqv '.[0].external')" true "external"
  eq "$(jqv '.[0].source')" external "source"
  eq "$(jqv '.[0].version')" 2.0 "version"
}

t_removing_an_adopted_app_deletes_its_file_and_entry() {
  adopt_demo
  cli list >/dev/null # the manager lists first, which is what adopts it
  cli remove hand-made; ok
  absent "$HOME/Applications/Hand-2.0.AppImage"
  absent "$HOME/.local/share/applications/hand.desktop"
}

t_an_adopted_app_whose_file_is_gone_is_forgotten() {
  adopt_demo
  cli list --json
  rm "$HOME/Applications/Hand-2.0.AppImage"
  cli list --json; eq "$(jqv 'length')" 0 "apps listed"
}

# --- locations, window, settings ----------------------------------------------
t_locations_lists_the_default_and_known_folders() {
  install_demo
  cli locations; ok
  eq "$(jqv '.default')" "$APPS" "default"
  eq "$(jqv '.options | map(select(.path == "'"$APPS"'")) | .[0].apps')" 1 "apps in the default folder"
}

t_window_starts_at_zero_and_remembers_what_it_is_told() {
  cli window; ok; eq "$(jqv '[.w,.h,.x,.y]|join(",")')" "0,0,0,0" "window"
  cli window --size 800x600 --offset -10,20 --setup-size 500x400; ok
  eq "$(jqv '[.w,.h,.x,.y]|join(",")')" "800,600,-10,20" "window"
  eq "$(jqv '[.setup.w,.setup.h]|join(",")')" "500,400" "setup window"
  cli window --reset; eq "$(jqv '[.w,.h,.x,.y]|join(",")')" "0,0,0,0" "window after reset"
  eq "$(jqv '.setup.w')" 500 "setup window is kept"
}

t_window_reads_as_unset_while_remembering_is_off() {
  cli window --size 800x600 --offset 5,6 >/dev/null
  printf 'REMEMBER_SIZE=false\nREMEMBER_POSITION=false\n' >>"$HOME/.config/startappimage/config"
  cli window; eq "$(jqv '[.w,.h,.x,.y]|join(",")')" "0,0,0,0" "window"
}

t_window_refuses_a_bad_size() {
  cli window --size big; refused "WIDTHxHEIGHT"
}

t_integration_reports_the_defaults() {
  cli integration; ok
  eq "$(jqv '.checkHours')" 6 "checkHours"
  eq "$(jqv '.rememberSize')" true "rememberSize"
  eq "$(jqv '.rememberPosition')" true "rememberPosition"
  eq "$(jqv '.launcher')" false "launcher"
  eq "$(jqv '.done')" false "done"
}

t_integration_carries_the_recommended_defaults() {
  cli integration; ok
  eq "$(jqv '.defaults.checkHours')" 6 "default hours"
  eq "$(jqv '.defaults.rememberSize')" true "default rememberSize"
  eq "$(jqv '.defaults.rememberPosition')" true "default rememberPosition"
  eq "$(jqv '.defaults.launcher')" true "default launcher"
  eq "$(jqv '.defaults.handler')" true "default handler"
  eq "$(jqv '.defaults.cli')" true "default cli"
  eq "$(jqv '.defaults.barIcon')" false "default barIcon"
}

t_the_default_a_reset_applies_is_the_default_a_fresh_install_reads() {
  cli integration
  eq "$(jqv '.defaults.rememberPosition')" "$(jqv '.rememberPosition')" "rememberPosition"
}

t_a_setting_nobody_changed_reads_as_its_default() {
  cli integration
  eq "$(jqv '.checkHours')" "$(jqv '.defaults.checkHours')" "hours"
  eq "$(jqv '.rememberSize')" "$(jqv '.defaults.rememberSize')" "rememberSize"
  mkdir -p "$HOME/.config/startappimage"; printf 'CHECK_HOURS=soon\n' >"$HOME/.config/startappimage/config"
  cli integration; eq "$(jqv '.checkHours')" 6 "hours when the saved value is not a number"
}

t_setup_stores_the_hours_and_marks_setup_done() {
  cli setup --check-hours 12; ok
  cli integration
  eq "$(jqv '.checkHours')" 12 "checkHours"
  eq "$(jqv '.done')" true "done"
}

t_setup_refuses_a_bad_number_of_hours() {
  cli setup --check-hours soon; refused "number of hours"
}

t_switching_remember_off_forgets_the_saved_window() {
  cli window --size 800x600 --offset 5,6; ok
  cli setup --remember-size false; ok
  cli window; eq "$(jqv '[.w,.h]|join(",")')" "0,0" "size forgotten"
  eq "$(jqv '[.x,.y]|join(",")')" "5,6" "offset kept"
  cli integration; eq "$(jqv '.rememberSize')" false "rememberSize"
  cli setup --remember-position false; ok
  cli window; eq "$(jqv '[.x,.y]|join(",")')" "0,0" "offset forgotten"
}

t_setup_switches_the_launcher_entry_on_and_off() {
  cli setup --launcher true; ok
  exists "$HOME/.local/share/applications/startappimage.desktop"
  cli integration; eq "$(jqv '.launcher')" true "launcher"
  cli setup --launcher false; ok
  absent "$HOME/.local/share/applications/startappimage.desktop"
}

t_setup_links_the_command_line_and_leaves_a_stranger_alone() {
  cli setup --cli true; ok
  eq "$(readlink "$HOME/.local/bin/startappimage")" "$CLI" "link"
  cli integration; eq "$(jqv '.cli.state')" ours "cli state"
  cli setup --cli false; ok
  absent "$HOME/.local/bin/startappimage"
  printf '#!/bin/sh\n' >"$HOME/.local/bin/startappimage"
  cli setup --cli true; refused "already exists"
  exists "$HOME/.local/bin/startappimage"
}

t_setup_json_confirms_and_names_the_piece_that_failed() {
  cli setup --check-hours 3 --json; ok; eq "$(jqv '.ok')" true "ok"
  printf '#!/bin/sh\n' >"$HOME/.local/bin/startappimage" 2>/dev/null || { mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\n' >"$HOME/.local/bin/startappimage"; }
  cli setup --cli true --json; [[ $CODE -ne 0 ]] || fail "expected a failure"
  eq "$(jqv '.ok')" false "ok"; eq "$(jqv '.field')" cli "field"; has "$(jqv '.error')" "already exists" "error"
}

t_setup_rejects_an_unknown_option() {
  cli setup --nonsense; refused "unknown option"
}

t_info_previews_an_appimage_and_knows_when_it_is_installed() {
  install_demo
  cli info "$HOME/Downloads/Demo.AppImage"; ok
  eq "$(jqv '.name')" "Demo App" "name"
  eq "$(jqv '.version')" 1.2 "version"
  eq "$(jqv '.installed')" true "installed"
  eq "$(jqv '.installedVersion')" 1.2 "installedVersion"
}

t_run_starts_an_installed_app_by_name() {
  install_demo
  printf '#!/bin/sh\necho "ran $*"\n' >"$APPS/demo-app.AppImage"
  cli run "Demo App"; ok; has "$OUT" "ran" "run"
}

t_info_ignores_an_icon_symlink_that_leaves_the_image() {
  fresh_home
  printf 'secret' >"$HOME/secret.txt"
  fake_appimage "$HOME/Downloads/Evil.AppImage" "Evil" 1 "link:$HOME/secret.txt"
  cli info "$HOME/Downloads/Evil.AppImage"; ok
  eq "$(jqv '.name')" "Evil" "name"
  eq "$(jqv '.icon')" "" "icon"
  ! grep -rqs secret "$HOME/.cache" || fail "the symlink target was copied into the cache"
}

t_info_never_runs_the_file() {
  local f="$HOME/Downloads/Demo.AppImage"
  fake_appimage "$f" "Demo App" 1.2
  cli info "$f"; ok
  eq "$(jqv '.name')" "Demo App" "name"
  [[ ! -e "$HOME/Downloads/squashfs-root" ]] || fail "info extracted next to the file"
  printf 'not an appimage' >"$HOME/Downloads/Plain.AppImage"; chmod +x "$HOME/Downloads/Plain.AppImage"
  cli info "$HOME/Downloads/Plain.AppImage"; refused "not a valid AppImage"
}

# --- runner -------------------------------------------------------------------
want=("$@")
selected() {
  local w; (( ${#want[@]} )) || return 0
  for w in "${want[@]}"; do [[ $1 == *"$w"* ]] && return 0; done
  return 1
}

while read -r t; do
  selected "$t" || continue
  FAILED_NOW=0
  if ( fresh_home; "$t"; exit $FAILED_NOW ) >"$SCRATCH/test.out" 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "${t#t_}"
    sed 's/^/        /' "$SCRATCH/test.out" | sed 's/^                /        /'
  fi
done < <(declare -F | awk '{print $3}' | grep '^t_')

printf 'tests/cli.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
