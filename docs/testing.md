# Testing StartAppImage

How a change gets checked, from the cheapest check to trying it in a live shell. Written so a person or an agent can pick it up cold, and so it can be improved: the last sections say how it works inside and what went wrong on the way.

| You want to | Use | Touches your desktop? |
|---|---|---|
| know the scripts and QML are not broken | `scripts/check.sh` (runs on every commit) | no |
| see the plugin run, click it, type into it | `scripts/dev` | no: a nested desktop out of reach of your mouse |
| watch that session | `scripts/dev watch` | a view-only window |
| try it on your own shell | `scripts/reload`, `scripts/pointer.sh` | yes: restarts your shell, moves your pointer |
| look over a recording | `scripts/sheet` | no |
| record the README animation | `scripts/hero.sh` ([recording-tours.md](recording-tours.md)) | `--nested`: no |

**The rule: test in `scripts/dev`, not on the real desktop.** A click or key sent to the real shell moves your pointer and types into your windows, a shell restart makes the bar blink, and a window left over your pointer can leave it behaving oddly. The test session has none of that. Use `reload` and `pointer.sh` only when the person asks to see it on their real shell.

## 1. Checks: `scripts/check.sh`

One command, no running shell needed. The pre-commit hook runs it and refuses a commit on `main`; CI runs the shell part.

```sh
scripts/check.sh          # all of it
scripts/lint-sh.sh        # bash -n and shellcheck over every script (rules in .shellcheckrc)
scripts/lint-qml.py       # qmllint, failing only on a warning the baseline does not list
omarchy plugin validate . # the manifest
```

- **Enable the hook once per clone:** `git config core.hooksPath .githooks`. Override for the rare commit that must go on `main`: `ALLOW_MAIN=1 git commit`.
- **QML warnings.** `qmllint` cannot see Quickshell's or Omarchy's types, so about ninety warnings are standing noise, kept in `scripts/qmllint-baseline.txt`. A *new* one (a misspelt id, a removed property) fails. If it is a real name from the shell, accept it with `scripts/lint-qml.py --update`. The idea is StartBar's, ported to Python.
- **Project rules** live in `scripts/check.sh`: no empty `iconText` (an icon whose glyph was lost in an edit), and the recorder's window geometry is computed, never typed.
- **What it cannot catch:** a layout that looks wrong, a click that misses, anything about the live shell. That is what the test session is for.

## 2. The test session: `scripts/dev`

A second Hyprland with its own Omarchy shell, running this checkout as the plugin, driven over its own Wayland socket. `scripts/dev --help` is the reference; this is the shape of a session:

```sh
scripts/dev up                       # 2 s. a nested desktop, out of your mouse's reach
scripts/dev open                     # open the manager there (setup, settings APP_ID, close)
scripts/dev shot /tmp/a.png          # screenshot it, then look at the file
scripts/dev click 536 146            # click the pixel you saw in the screenshot
scripts/dev type "pdf"               # type; scripts/dev key Escape for a named key
scripts/dev errors                   # what the plugin logged, noise removed (0 = clean)
# edit a .qml file ...
scripts/dev reload                   # 4 s. restarts the nested shell only; loads uncommitted files
scripts/dev watch                    # optional: a window showing the session live
scripts/dev down                     # always, when done
```

Every command prints one line and exits non-zero when it did not do what it says (`dev reload FAILED ... qml-errors 2`, `dev open: the window did NOT open`).

- **Pixels** are the session's screen, 1280×800, 0,0 at the top-left, exactly as in a `dev shot`. Read the pixel off the screenshot and click it; nothing is scaled or offset.
- **A click outside the card closes it**, as it would for a person: screenshot before you click.
- **No commit or push is needed.** The plugin in the session is a link to this checkout, so `reload` loads what is on disk. (Your real shell is different: its plugin is a separate clone, see section 3.)
- **It closes itself** after `DEV_TTL` seconds (default 1800), and a stale session is cleaned up by the next `up`. End it yourself with `down`: the session holds a virtual monitor and about a dozen processes.
- **Your data is safe.** The session has a home of its own (`$XDG_RUNTIME_DIR/startappimage-dev/nest/home`) with *copies* of the app's data, so installing, updating, removing and renaming there never touch your apps. Its bar starts with a "TEST SESSION" label, because the window's own title is fixed by the nested compositor ("aquamarine - WAYLAND-N") and the desktop inside looks exactly like yours.

### Watching it: `scripts/dev watch`

Opens an ordinary window (`scripts/dev-view.qml`) that shows the session five times a second. Drag it, cover it, resize it, send it to the scratchpad: your pointer is the normal arrow over it and a click does nothing, because nothing in it listens. `scripts/dev unwatch` closes it. It ends with the session.

The session's *own* window is never put on your screen. That was tried and it was wrong: see "What went wrong" below.

## 3. Your real desktop: `scripts/reload`, `scripts/pointer.sh`

For when someone wants to see the change in their own shell.

- `scripts/reload [open | setup | settings ID] [--shot FILE]` syncs the installed plugin to this checkout's *pushed* HEAD, restarts the shell (the bar blinks), reports plugin errors, and optionally opens a window and screenshots it. It prints `reload ok branch@sha restart 6.5s qml-errors 0`. `scripts/reload --check` only reports whether the installed plugin matches. Commit and push first: the installed plugin is a separate git clone, and `omarchy plugin disable` and `enable` do **not** load new QML, only a full shell restart does.
- `scripts/pointer.sh click PX PY` clicks the pixel PX,PY of a screenshot of the focused monitor (it works out the monitor's place and scale). It moves the real pointer, so only use it when asked.

## 4. Looking over a recording: `scripts/sheet`

`scripts/sheet FILE.avif|gif [--every S] [--width PX] [--cols N] [--out FILE]` makes one contact sheet image from an animation, so a whole recording can be checked at once. It knows that an AVIF holds two video streams (the still cover, then the animation) and reads the second.

## 5. How it works inside

```
scripts/dev ──► scripts/nested/session.sh ──► Hyprland (nested) ──► quickshell: the Omarchy shell + this plugin
   │                  (sandbox, start, stop)         │ a window of your compositor, moved to a virtual monitor
   │                                                 │   at x = 20000, which a real pointer cannot reach
   ├─ click, type, key ──► scripts/nested/vptr (virtual pointer) and wtype (virtual keyboard), on the session's socket
   ├─ shot ───────────────► grim, on the session's socket
   └─ errors ─────────────► the session's shell log, filtered
```

- **`scripts/nested/session.sh`** is shared with the recorder (`scripts/tour.sh --nested`). It builds the sandbox home (Omarchy's themes copied, a `shell.json` that keeps your bar layout but only Omarchy's own widgets plus this plugin, the plugin linked to the checkout, copies of the app's data), starts the nested Hyprland under its own D-Bus that starts nothing, and stops everything it started.
- **Input.** `scripts/nested/vptr.c` is a tiny client of the `wlr-virtual-pointer` protocol (built on first use into the session's folder). Keys use `wtype`. Both talk to the nested compositor's socket, so nothing reaches your real seat.
- **Your mouse and keyboard are switched off inside the session.** The host seat gives the nested compositor two devices, `wl_pointer` and `wl_keyboard`; its config disables both (`hl.device({ name = ..., enabled = false })`). The virtual devices are separate and keep working. This was checked with a control: the same real click closes a card when the devices are left on (`NEST_HOST_INPUT=1`) and does nothing when they are off.
- **The far monitor.** `up` creates a headless monitor `DEVTEST` 20,000 px to the right and moves the window there. Sliding a mouse off the edge of your screen stops at the edge, so the window cannot be reached. `down` removes the monitor.
- **The noise filter.** `errors` and `reload` count only lines that name this plugin's files (`io.github.bmaltais.startappimage`) and carry a warning or error, minus known noise (layout "recursive rearrange", "Local plugin changed", qmlscanner, portal, `qt.svg`). Omarchy's own errors (for example the bar's "Cannot assign to read-only property moduleName" for the label widget) are not ours and are not counted.

## 6. What went wrong on the way, and the rule it left

Each of these cost a round of testing; they are why the design is what it is.

- **Never put the nested compositor's window under a real pointer.** While a pointer is over it, the nested compositor chooses the cursor image: it hid the pointer, showed a hand, and left the pointer behaving oddly after a window drag. A transparent *shield* over the window cured the input but showed a "block" cursor and stopped the window being dragged, since it is a separate overlay. Hence the far monitor for the session and the separate view window for watching. The recorder's `--nested` mode uses the same far monitor and view window.
- **Do not change the nested compositor's cursor options at runtime** (`hl.config({ cursor = ... })` through `hyprctl eval`): it crashed the nested Hyprland.
- **A reused socket name hid the session.** The nested compositor's socket is `wayland-N` and the number is reused, so finding "the new socket" by a name that was absent before failed after an aborted cleanup left a stale file. It is found by being created after the start, and `down` removes its own socket and instance folder.
- **`pgrep -f` matches its own shell.** A pattern passed to `pgrep -f` in a command line also matches that command line. Find processes by an environment marker (`procs_with` in `scripts/dev`) or use a `[x]` bracket pattern.
- **Plugin reload does not load QML.** Only a full shell restart does. Both `reload` and `dev reload` do that restart.
- **Icons lost in an edit.** Private-use glyphs in QML were dropped when files were rewritten, leaving `iconText: ""`; `check.sh` now fails on it. Write icons as `\uXXXX` escapes.
- **ffprobe reads one frame of an AVIF.** It shows the still cover image first; the animation is the second video stream (`-f mov -map 0:v:1`). `scripts/sheet` does this for you.

## 7. Limits, and ideas for improving it

- **Hyprland only, and a newer Hyprland than 0.56 may change the Lua API** (`hl.dsp.window.move`, `hl.device`, `hl.monitor`) that `scripts/nested/session.sh` and `scripts/dev` use.
- **One session at a time** (a fixed state folder and monitor name).
- **The view window is a picture, not the session**: five frames a second, so a fast animation looks choppy, and the cursor of the session is whatever the screenshot has in it.
- **`dev click` has no hover, drag or scroll.** `vptr` can drag (the recorder uses it); `dev` could expose `drag` and `scroll`.
- **Ideas:** a `dev run SCRIPT` that replays a list of steps and fails on the first miss (a smoke test for CI-less checking); `dev shot --diff` against the last shot; installing `wl-mirror` or a Quickshell `ScreencopyView` would replace the five-frames-a-second picture with a live one.

## Where the files are

| Path | What it is |
|---|---|
| `scripts/check.sh`, `lint-sh.sh`, `lint-qml.py`, `qmllint-baseline.txt`, `.shellcheckrc` | the checks |
| `.githooks/pre-commit`, `.github/workflows/check.yml` | the hook (refuses `main`, runs the checks) and the CI job (shellcheck) |
| `scripts/dev`, `scripts/dev-view.qml` | the test session and its view window |
| `scripts/nested/` | session start/stop and the virtual pointer, shared with the recorder |
| `scripts/reload`, `scripts/pointer.sh` | for the real desktop |
| `scripts/sheet` | contact sheets |
| `scripts/tour.sh`, `scripts/tours/`, `scripts/tour-banner.qml` | the recorder ([recording-tours.md](recording-tours.md)) |
