# Testing StartAppImage

How a change gets checked, from the cheapest check to trying it in a live shell. The test session itself (`scripts/dev`), the recorder (`scripts/tour.sh`) and `scripts/sheet` are the shared devkit's, in `scripts/devkit` ([omarchy-plugin-devkit](https://github.com/bmaltais/omarchy-plugin-devkit)); its guides say how they work and why: [testing](../scripts/devkit/docs/testing.md), [how it works, and what went wrong on the way](../scripts/devkit/docs/how-it-works.md), [configuration](../scripts/devkit/docs/configuration.md). This page is what is StartAppImage's own.

| You want to | Use | Touches your desktop? |
|---|---|---|
| know the scripts and QML are not broken, and the command line still behaves | `scripts/check.sh` (runs on every commit) | no |
| run only the command-line tests | `tests/cli.sh [word ...]` | no: a throwaway `$HOME` |
| see the plugin run, click it, type into it | `scripts/dev` | no: a nested desktop out of reach of your mouse, with a home of its own and a guard in front of its `PATH` |
| watch that session | `scripts/dev watch` | a view-only window |
| try it on your own shell | `scripts/reload`, `scripts/pointer` | yes: restarts your shell, moves your pointer |
| look over a recording | `scripts/sheet` | no |
| record the README animation | `scripts/hero.sh` ([recording-tours.md](recording-tours.md)) | no |

**The rule: test in `scripts/dev`, not on the real desktop.** A click or key sent to the real shell moves your pointer and types into your windows, a shell restart makes the bar blink, and a window left over your pointer can leave it behaving oddly. The test session has none of that. Use `reload` and `pointer` only when the person asks to see it on their real shell.

## 1. Checks: `scripts/check.sh`

One command, no running shell needed: `scripts/check.sh` is the devkit's `check` (shell scripts, the devkit's project rules, qmllint, the manifest) plus the steps `devkit_check` adds in `devkit.conf` (`tests/cli.sh` and the icon check). The pre-commit hook runs it and refuses a commit on `main`; CI runs the same, where the QML and manifest steps skip themselves.

- **Enable the hook once per clone:** `scripts/devkit/bin/pre-commit --install`. Override for the rare commit that must go on `main`: `ALLOW_MAIN=1 git commit`.
- **QML warnings.** `scripts/qmllint` fails only on a warning `scripts/qmllint-baseline.txt` does not list; about ninety are standing noise, because `qmllint` cannot see Quickshell's or Omarchy's types. If a new one is a real name from the shell, accept it with `scripts/qmllint --update`. Some warnings are real bugs and can never be baselined (a property that hides one of `Item`'s, such as `state`): rename it.
- **Project rules** are the devkit's `bin/lint` (no `setsid -f` launch that keeps the caller's output open) and `icons` in `devkit.conf`: no empty `iconText` (an icon whose glyph was lost in an edit).
- **Command-line tests.** `tests/cli.sh` runs `bin/startappimage` against a throwaway `$HOME` with a fake AppImage and asserts exit codes, JSON and files on disk (add, list, config, set, remove, adopted apps, locations, window, setup). A test is a `t_*` function; name words on the command line select tests. It never touches the network, the real home or the desktop, so it also runs in CI. Update checks against GitHub are not covered yet.
- **What it cannot catch:** a layout that looks wrong, a click that misses, anything about the live shell. That is what the test session is for.

## 2. The test session: `scripts/dev`

`scripts/dev` is the devkit's `dev`, run for this checkout; `devkit.conf` tells it the plugin's id and layer, the sandbox (copies of the app's data, and of each AppImage a manifest names, so a rename, a hide or an update in the session never reaches a real file), and the commands below.

```sh
scripts/dev up                       # a nested desktop, out of your mouse's reach, and a window showing it live
scripts/dev open                     # open the manager there (setup, settings APP_ID, close)
scripts/dev shot /tmp/a.png          # screenshot it, then look at the file
scripts/dev click 826 387            # click the pixel you saw (rclick, scroll PX PY N, move PX PY: scripts/dev --help)
scripts/dev key Escape               # press a key; scripts/dev type TEXT for text
scripts/dev errors                   # what the plugin logged, noise removed (0 = clean)
# edit a .qml file ...
scripts/dev reload                   # restarts the nested shell only; loads uncommitted files
scripts/dev down                     # always, when done
```

### Retaking the README screenshots: `scripts/screenshots.sh`

Runs the whole thing in the session: `up` (with `DEV_SIZE` if you want another screen), window sizes reset in the sandbox, a flat backdrop window behind the cards, `open`, `setup`, `settings`, the install card, `shot` of each, a crop centred on the screen, then `down`. `SHOTS_OUT=DIR` writes elsewhere, for a trial run. The install card needs an `~/Applications` of the session's own, which the script builds, so it shows `~/Applications` and not your home.

## 3. Your real desktop: `scripts/reload`, `scripts/pointer`

For when someone wants to see the change in their own shell. `scripts/reload [open | setup | settings APP_ID] [--shot FILE | --check]` is the devkit's `reload`: the plugin is installed as a git clone, so **commit and push the branch first**; it fast-forwards the installed clone to it, restarts the shell (the bar blinks) and reports errors. `scripts/pointer click PX PY` is the devkit's `pointer`: it moves the real pointer, so only when asked.

## 4. Looking over a recording: `scripts/sheet`

`scripts/sheet FILE.avif|gif [--every S] [--width PX] [--cols N] [--out FILE]` makes one contact sheet image from an animation (the devkit's `sheet`).

## Where the files are

| Path | What it is |
|---|---|
| `devkit.conf` | what the devkit needs to know about this plugin: its id, layer, sandbox, commands |
| `scripts/devkit/` | the devkit, a git submodule (clone with `--recurse-submodules`, or `git submodule update --init`; update with `git -C scripts/devkit checkout vX.Y.Z`, then commit): development tooling, so it is not in what a user installs |
| `scripts/dev`, `tour.sh`, `sheet`, `reload`, `pointer`, `qmllint`, `check.sh` | two-line wrappers of the devkit's `dev`, `tour`, `sheet`, `reload`, `pointer`, `qmllint`, `check` for this checkout |
| `scripts/qmllint-baseline.txt`, `.shellcheckrc` | the standing QML warnings, and the shellcheck rules |
| `.githooks/pre-commit`, `.github/workflows/check.yml` | the hook (refuses `main`, runs the checks) and the CI job (the devkit's `app-check.yml`) |
| `tests/cli.sh` | the command-line behaviour tests |
| `scripts/screenshots.sh`, `scripts/preview.sh` | the README screenshots and the marketplace picture |
| `scripts/tours/`, `scripts/hero.sh` | this app's tour ([recording-tours.md](recording-tours.md)) |
