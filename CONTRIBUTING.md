# Contributing to StartAppImage

## Layout

| Path | What it is |
|---|---|
| `manifest.json` | The Omarchy plugin manifest (a `service` that stays loaded) |
| `Service.qml` | State, every call to the CLI, the IPC entry points and the window |
| `ManagerView.qml`, `AppRow.qml` | The manager and the look of one app |
| `InstallView.qml` | The install card shown when an `.AppImage` is opened |
| `SettingsWindow.qml` | The settings window component: header, page list, rows, footer. Both settings windows are built on it |
| `SetupView.qml` | The main settings: launcher entry, file handler, command line, bar icon, update checks, window memory |
| `SettingsView.qml` | One app's settings: name, launch options, source, folder |
| `SettingsPill.qml` | A footer button of the settings windows |
| `BarWidget.qml` | The optional Omarchy bar icon |
| `ScrollTrack.qml` | The scroll bar |
| `Chip.qml`, `Field.qml` | A selectable choice and a text field |
| `bin/startappimage` | The command line: install, list, update, remove, settings. It is the only part that touches files |
| `assets/` | The launcher icon |
| `screenshots/`, `preview.png` | Images used by the README and the plugin preview; retake them with `scripts/screenshots.sh` (it runs in the nested test session, see [docs/testing.md](docs/testing.md)), then `scripts/preview.sh` |
| `scripts/tour.sh`, `scripts/tours/`, `devkit.conf` | The tour recorder (the shared devkit's, in `scripts/devkit`) run for this checkout, this app's tour, and what the devkit needs to know about the app. `screenshots/hero.avif` (the animation at the top of the README) is retaken with `scripts/hero.sh --install` when a step of the tour changes. See `docs/recording-tours.md` |
| `scripts/check.sh`, `qmllint`, `.githooks/`, `.github/workflows/check.yml` | The checks (the devkit's `check` and `qmllint`), the pre-commit hook (`scripts/devkit/bin/pre-commit --install` once per clone; it refuses commits on `main`) and the CI job |
| `scripts/dev`, `sheet`, `reload`, `pointer` | Testing tools, all wrappers of the devkit's in `scripts/devkit`: a nested test session, contact sheets, the real-shell reload, a pointer click. See `docs/testing.md` |
| `tests/cli.sh` | Behaviour tests for `bin/startappimage` in a throwaway `$HOME`; part of `scripts/check.sh` and CI |
| `docs/testing.md` | How a change is checked and tried, and what went wrong before |
| `docs/ui-standards.md` | How the UI looks and behaves, and why. Read it before changing the UI, and update it when a design decision changes |

The QML never edits files itself: it asks `bin/startappimage` and reads its JSON (`list --json`, `info`, `config`, `locations`, `integration`, `check --json`).

## Development install

Clone with `git clone --recurse-submodules` (or run `git submodule update --init` in an existing clone): `scripts/devkit`, the test session and recorder, is a submodule of the shared [omarchy-plugin-devkit](https://github.com/bmaltais/omarchy-plugin-devkit). It is development tooling, so it is not in what `omarchy plugin add` installs.

The plugin is a `service` with `keepLoaded`, so the shell keeps the running copy and does not reload it when a file changes. Restart the shell after each edit:

```sh
omarchy plugin validate .
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.bmaltais.startappimage
omarchy restart shell
```

Run it from a checkout by linking it into `~/.config/omarchy/plugins/io.github.bmaltais.startappimage`, or copy the checkout there. Then:

```sh
bin/startappimage setup --launcher true --handler true   # launcher entry, icon and the .AppImage handler
omarchy-shell io.github.bmaltais.startappimage open
```

## Trying the CLI safely

Everything lives under `$HOME`, so run it against a throwaway home to leave your own apps alone:

```sh
H=$(mktemp -d); HOME=$H bin/startappimage add ~/Downloads/Some.AppImage --dir '~/Tools'
HOME=$H bin/startappimage list
```

## Style

- Match the Start family: colours from `Color`, sizes from `Style`, buttons from `qs.Ui`, so it follows the Omarchy theme.
- Keep launcher and file work in the CLI, with the same guards: inside `$HOME`, nothing deleted that is not an `.AppImage`.
- Describe what the app does when it fails; never fail silently.
