# Testing StartAppImage

How a change gets checked, from the cheapest check to trying it in a live shell. The test session itself (`scripts/dev`), the recorder (`scripts/tour.sh`) and `scripts/sheet` are the shared devkit's, in `scripts/devkit` ([omarchy-plugin-devkit](https://github.com/bmaltais/omarchy-plugin-devkit)); its guides say how they work and why: [testing](../scripts/devkit/docs/testing.md), [how it works, and what went wrong on the way](../scripts/devkit/docs/how-it-works.md), [configuration](../scripts/devkit/docs/configuration.md). This page is what is StartAppImage's own.

| You want to | Use | Touches your desktop? |
|---|---|---|
| know the scripts and QML are not broken, and the command line still behaves | `scripts/check.sh` (runs on every commit) | no |
| run only the command-line tests | `tests/cli.sh [word ...]` | no: a throwaway `$HOME` |
| see the plugin run, click it, type into it | `scripts/dev` | no: a nested desktop out of reach of your mouse, with a home of its own and a guard in front of its `PATH` |
| watch that session | `scripts/dev watch` | a view-only window |
| try it on your own shell | `scripts/reload`, `scripts/pointer.sh` | yes: restarts your shell, moves your pointer |
| look over a recording | `scripts/sheet` | no |
| record the README animation | `scripts/hero.sh` ([recording-tours.md](recording-tours.md)) | no |

**The rule: test in `scripts/dev`, not on the real desktop.** A click or key sent to the real shell moves your pointer and types into your windows, a shell restart makes the bar blink, and a window left over your pointer can leave it behaving oddly. The test session has none of that. Use `reload` and `pointer.sh` only when the person asks to see it on their real shell.

## 1. Checks: `scripts/check.sh`

One command, no running shell needed. The pre-commit hook runs it and refuses a commit on `main`; CI runs the shell part.

```sh
scripts/check.sh          # all of it
scripts/lint-sh.sh        # bash -n and shellcheck over every script, the devkit's included (rules in .shellcheckrc)
scripts/devkit/bin/lint . # the devkit's project rules (a background launch must redirect its output ...)
scripts/lint-qml.py       # qmllint, failing only on a warning the baseline does not list
omarchy plugin validate . # the manifest
```

- **Enable the hook once per clone:** `git config core.hooksPath .githooks`. Override for the rare commit that must go on `main`: `ALLOW_MAIN=1 git commit`.
- **QML warnings.** `qmllint` cannot see Quickshell's or Omarchy's types, so about ninety warnings are standing noise, kept in `scripts/qmllint-baseline.txt`. A *new* one (a misspelt id, a removed property) fails. If it is a real name from the shell, accept it with `scripts/lint-qml.py --update`. The idea is StartBar's, ported to Python.
- **Project rules** live in `scripts/check.sh` and the devkit's `bin/lint`: no empty `iconText` (an icon whose glyph was lost in an edit), and no `setsid -f` launch that keeps the caller's output open.
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

## 3. Your real desktop: `scripts/reload`, `scripts/pointer.sh`

For when someone wants to see the change in their own shell: `scripts/reload` copies this checkout over the installed plugin and restarts the shell (the bar blinks); `scripts/pointer.sh click PX PY` moves the real pointer, so only when asked.

## 4. Looking over a recording: `scripts/sheet`

`scripts/sheet FILE.avif|gif [--every S] [--width PX] [--cols N] [--out FILE]` makes one contact sheet image from an animation (the devkit's `sheet`).

## Where the files are

| Path | What it is |
|---|---|
| `devkit.conf` | what the devkit needs to know about this plugin: its id, layer, sandbox, commands |
| `scripts/devkit/` | the devkit (a git subtree: `git subtree pull --prefix scripts/devkit https://github.com/bmaltais/omarchy-plugin-devkit vX.Y.Z --squash`) |
| `scripts/dev`, `scripts/tour.sh`, `scripts/sheet` | two-line wrappers of the devkit's `dev`, `tour`, `sheet` for this checkout |
| `scripts/check.sh`, `lint-sh.sh`, `lint-qml.py`, `qmllint-baseline.txt`, `.shellcheckrc` | the checks |
| `.githooks/pre-commit`, `.github/workflows/check.yml` | the hook (refuses `main`, runs the checks) and the CI job (shellcheck, the CLI tests) |
| `tests/cli.sh` | the command-line behaviour tests |
| `scripts/screenshots.sh`, `scripts/preview.sh` | the README screenshots and the marketplace picture |
| `scripts/tours/`, `scripts/hero.sh` | this app's tour ([recording-tours.md](recording-tours.md)) |
| `scripts/reload`, `scripts/pointer.sh` | for the real desktop |
