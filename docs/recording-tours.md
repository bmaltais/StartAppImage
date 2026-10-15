# Recording tours

How to record a short GIF that shows an app being used, with `scripts/tour.sh`. It made `screenshots/hero.gif`, the tour at the top of the README. The recorder is **not specific to StartAppImage**: every Start app can use it, each with its own *tour file* that says what to do.

- [Run the StartAppImage tour](#run-the-startappimage-tour)
- [What you need](#what-you-need)
- [What happens when you run it](#what-happens-when-you-run-it)
- [Writing a tour for an app](#writing-a-tour-for-an-app)
- [Reference](#reference)
- [How it works inside](#how-it-works-inside)
- [Troubleshooting](#troubleshooting)
- [Human-like input](#human-like-input)
- [Reading time](#reading-time)
- [Nested mode](#nested-mode---nested)
- [Using it in another Start app](#using-it-in-another-start-app)

## Run the StartAppImage tour

```sh
scripts/hero.sh              # records it, leaves the GIF in /tmp/hero.gif for a look
scripts/hero.sh --install    # records it and copies it to screenshots/hero.gif
scripts/hero.sh --yes        # does not ask first (for when another script runs it)
scripts/hero.sh --nested     # runs it in a window you can watch, in a sandbox (see "Nested mode")
```

`scripts/hero.sh` is a shortcut for `scripts/tour.sh scripts/tours/hero.sh`. It takes a little over two minutes, of which the tour itself is about one. A red window in the middle of your screen first asks you to confirm: **Proceed** starts the recording, **Cancel** (or Esc) stops before anything is touched. After that, **leave the mouse and keyboard alone** until the window turns green and says the tour is done: the pointer is driving a virtual screen and typing goes there.

Retake the tour when a step of it changes (a button moves, a label is renamed), and look at the GIF before you commit it: it clicks the real app at fixed places, so a changed layout makes it miss.

## What you need

- **Hyprland** (it uses its `hyprctl` and the `hl.dsp.*` dispatchers of 0.56) on **Omarchy**.
- **Tools**: `hyprctl`, `jq`, `grim`, `ffmpeg` (with the `drawtext` filter), ImageMagick (`magick`), `imv`, `quickshell` and `ydotool`. The recorder checks for them and says which one is missing.
- **ydotool with its daemon running and a writable `/dev/uinput`**, to move the real pointer and type. If `ls -l /dev/uinput` shows it is not writable by you, add yourself to the group that owns it (on Omarchy, `wheel`) and give that group access with a udev rule: `KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="wheel", MODE="0660", OPTIONS+="static_node=uinput"` in `/etc/udev/rules.d/80-uinput.rules`, then reload the rules. `ydotoold --socket-path=$XDG_RUNTIME_DIR/.ydotool_socket --socket-own=$(id -u):$(id -g)` starts the daemon.
- **The app running**, and whatever the tour uses installed in it (the StartAppImage tour uses ArtCraft Launcher with a GitHub source, and PdfCraft).

## What happens when you run it

1. A red window appears in the middle of your real screen, "Record the StartAppImage tour?", saying what is about to happen and asking you not to touch the mouse or keyboard. **Proceed** continues; **Cancel** or Esc exits with nothing changed. (`--yes` skips this.)
2. A **virtual monitor** (1280×800, `TOURREC`) is created to the right of your screens and focused, with a plain full-screen backdrop (`imv`) on it. Your own screen is left alone.
3. The tour's `tour_prepare` runs: it saves whatever the tour will change and sets things up. If the tour asks (`TOUR_RESTART_SHELL=1`), the Omarchy shell is restarted so it reads the change.
4. `tour_setup` runs, then **filming starts**: `grim` takes a frame of the virtual monitor over and over, each stamped with its time.
5. `tour_play` runs: the steps, moving the real pointer and typing with `ydotool`. Each `cap` shows a caption from then until the next one, and the red window, now saying "Recording the StartAppImage tour. Do not touch the mouse or the keyboard", shows the step it is on.
6. Filming stops. The frames become a video, the captions are drawn on it with `ffmpeg`, and it is turned into a GIF (10 frames a second, 1200 px wide, 128 colours).
7. **Everything is put back** (`tour_restore`, the monitor, focus, the pointer, a shell restart if one was made), the window turns green and says the tour is done for a few seconds, and a notification says so too. This also happens when you interrupt it with Ctrl+C.

## Writing a tour for an app

A tour is a story, not a feature list: one thing a person does per step, with a caption in plain words ("One click to update"). Aim for under a minute.

### 1. A minimal tour file

This one opens StartAppImage's manager and searches. It is a complete tour:

```bash
# shellcheck shell=bash
TOUR_TITLE=StartAppImage              # the app's name, for the banner
TOUR_OUT=screenshots/example.gif      # where --install puts the GIF
TOUR_LAYER=omarchy-startappimage      # the app window's layer-shell name (see below)

tour_play() {
  cap "Open the manager"
  omarchy-shell io.github.bmaltais.startappimage open
  sleep 1.5
  glide 640 300
  sleep 1

  cap "Search for an app"
  click 640 196 0.5
  typed "pdf"
  sleep 1.5
  esc; sleep 0.5
}
```

Run it with `scripts/tour.sh path/to/example.tour.sh` (add `--install` to copy the result to `TOUR_OUT`).

### 2. Find the window's layer name

Keys and typing are only sent while the app's window is up on the virtual monitor, so they can never land on anything else. The recorder finds it by its layer-shell namespace, `TOUR_LAYER`. For a Quickshell plugin this is its `WlrLayershell.namespace`; to see what is there, open the window and run `hyprctl layers -j | jq '[.. | .namespace? // empty] | unique'`. Without `TOUR_LAYER`, `key`, `typed` and `esc` do nothing.

### 3. Find where to click

Coordinates are on the virtual monitor, `0,0` at its top-left, and do not change from run to run **if the window opens the same way each time**. Make that so: reset anything remembered (a saved window size or position) in `tour_prepare`, and restart the shell if it only reads that at start (`TOUR_RESTART_SHELL=1`).

To read coordinates off the screen, make a virtual monitor yourself, open the app on it and take a screenshot:

```sh
X=$(hyprctl monitors -j | jq -r '[.[] | .x + .width] | max')
hyprctl output create headless TOURREC
hyprctl eval "hl.monitor({ output = \"TOURREC\", mode = \"1280x800@60\", position = \"${X}x0\", scale = 1 })"
hyprctl dispatch "hl.dsp.focus({ monitor = \"TOURREC\" })"      # apps open on the focused monitor
# ... open the app, then:
grim -o TOURREC /tmp/shot.png                                     # look at it: the pixel you see is the coordinate you use
# click something by hand to see the next state:
hyprctl dispatch "hl.dsp.cursor.move({ x = $((X + 500)), y = 300 })"; ydotool mousemove -x 1 -y 0; ydotool mousemove -x -1 -y 0; ydotool click 0xC0
# when you are done:
hyprctl output remove TOURREC
hyprctl dispatch "hl.dsp.focus({ monitor = \"DP-3\" })"           # your own monitor's name
```

Take a screenshot at every state the tour passes through, and write the coordinates down as you go. Screenshots on the virtual monitor are exactly 1280×800, so what you read is what you click.

### 4. Look at it, and tune the timing

Run without `--install`, then look at the GIF. A contact sheet shows every step at a glance:

```sh
ffmpeg -y -i /tmp/hero.gif -vf "fps=1/3.5,scale=520:-1" /tmp/f_%02d.png && magick montage /tmp/f_*.png -tile 3x -geometry +4+4 /tmp/sheet.png
```

Give each caption enough time to be read (about 3 seconds for a short one), and let animations finish before the next click. Use `wait_until` for things that take as long as they take (a download), not a fixed `sleep`.

### 5. Putting things back

Anything the tour changes must come back. Save it in `tour_prepare`, restore it in `tour_restore`; the recorder calls `tour_restore` however the run ends. The StartAppImage tour, for example, saves the windows' size and position and restores them, makes one app look a version behind and restores its record, and switches the bar icon off and on (and restores whichever state it started in).

## Reference

### Variables a tour file sets

| Variable | Meaning | Default |
|---|---|---|
| `TOUR_TITLE` | The app's name, for the banner. **Required.** | |
| `TOUR_OUT` | The GIF's path in the repo, used by `--install` | `screenshots/hero.gif` |
| `TOUR_LAYER` | The app window's layer-shell namespace; needed for `key`, `typed` and `esc` | none |
| `TOUR_STEPS` | How many steps (`cap` calls), for "Step 2 of 6" | unknown |
| `TOUR_SIZE` | The virtual monitor, `WxH` | `1280x800` |
| `TOUR_BG` | The backdrop colour | `#262a36` |
| `TOUR_RESTART_SHELL` | `1` to restart the Omarchy shell after `tour_prepare` and again at the end | `0` |
| `TOUR_FONT` | The caption font file | JetBrains Mono Nerd Font Bold |

### Functions a tour file defines

| Function | Runs | Use it to |
|---|---|---|
| `tour_requires` | first | check what the tour needs; print a reason and return non-zero if it is missing |
| `tour_prepare` | after the monitor and backdrop are up | save what the tour will change, and reset to a known state |
| `tour_setup` | after the shell restart (if any), just before filming | make the changes that must be visible in the film |
| `tour_play` | while filming. **Required.** | the steps |
| `tour_restore` | at the end, or when interrupted | put back whatever the tour changed |

### Helpers for `tour_play`

| Helper | Does |
|---|---|
| `cap "text"` | Shows this caption, at the bottom, from now until the next `cap`. Also updates the banner. Avoid `:` and `'` in the text (they are special to `ffmpeg`). |
| `glide X Y` | Moves the pointer there in small steps, so it is seen to travel. |
| `click X Y [pause]` | Glides there, clicks, then waits `pause` seconds (default 0.9). |
| `drag DX DY` | Presses the button where the pointer is, moves by that much, lets go. The move is a little larger than asked, so check what it does. |
| `typed "text"` | Types it, slowly enough to be seen. |
| `key CODE:1 CODE:0 …` | Presses keys (Linux key codes: `1` is Escape, `28` Enter, `14` Backspace, `29` Ctrl, `30` A). |
| `esc` | Presses and releases Escape. |
| `wait_until 'command' [seconds]` | Polls a shell command until it succeeds, up to `seconds` (default 30). |
| `at X Y` | Puts the pointer there at once (with a nudge, so hovers fire). |
| `MON`, `MX`, `W`, `H`, `TMP`, `REPO` | The monitor's name, its x in the layout, its size, a scratch folder and the repo root. |

Other commands in `tour_play` are ordinary shell: opening the app (`omarchy-shell … open`), `sleep`, reading files.

## How it works inside

- **A virtual monitor**, because the real screen is yours: the recorder must not touch it, show its contents, or be disturbed by what is on it. Omarchy's screen recorder cannot see a virtual monitor, so frames are taken with `grim` (cursor included) in a loop, each file named for the time it was taken.
- **Frame timing.** The frames are joined with `ffmpeg`'s concat demuxer, each shown for the time until the next one, so the video plays at the speed things really happened even though grabs take a variable time.
- **Captions** are drawn by `ffmpeg`'s `drawtext`, each enabled between the time it was said and the time of the next.
- **The GIF** uses a two-pass palette (`palettegen` then `paletteuse`) at 10 frames a second and 1200 px wide, which keeps a minute of UI to a few MB. Change those numbers at the end of `scripts/tour.sh` if you need a smaller or sharper file.
- **The pointer** is moved with `hyprctl dispatch hl.dsp.cursor.move`, which places it, followed by a 1 px `ydotool` nudge, which makes Hyprland fire a real motion event so hovers work. Clicks and typing go through `ydotool`.
- **The red window** (`scripts/tour-banner.qml`, which in `--nested` mode is a strip above the nested window plus the shield over it), run by `quickshell` as its own small instance next to the Omarchy shell (so a shell restart does not touch it): a centred, always-on-top layer-shell window on the real monitor. It runs twice: first in *confirm* mode (Proceed and Cancel, the answer is written to a file the recorder waits on), then in *status* mode, where it shows a text file the recorder rewrites at each step and turns green when it is told the tour is done. It redraws in place, so it does not flicker, and in status mode it takes no keyboard focus. Notifications cannot do this job: the Omarchy shell's, and Hyprland's own, appear on the focused monitor, which is the virtual one while recording, so they would end up in the GIF. (A first version used a terminal window that redrew its text four times a second; it flickered.)
- **Keys only when the app is up.** `key`, `typed` and `esc` check that the app's layer is mapped on the virtual monitor first. Otherwise the keys would go to the backdrop window (a stray `q` quits `imv`) or somewhere worse.

## Troubleshooting

- **"window not up, skipped keys …"**: the app's window was not up when the keys were due, so they were not sent. A step before it did not open the window, or closed it (a single Esc already closes some windows, so a second Esc has nothing to close). Fix the earlier step; use `wait_until` rather than `sleep` if the window can be slow.
- **Clicks miss**: the layout is not what you measured. The usual cause is a remembered size or position: reset it in `tour_prepare` and use `TOUR_RESTART_SHELL=1`. Or the app's window opened on the wrong monitor, because the virtual one was not focused (the recorder refocuses it after a restart).
- **Toggles**: an `open` command that is a toggle closes the window when it is already up. Make sure of the state a step starts in.
- **Frames look empty or half-drawn at the start or end**: the first second is cut on purpose. Add a `sleep` at the start of the first step if the app needs longer to appear.
- **A run was killed with `kill -9`**: the cleanup did not run. `hyprctl output remove TOURREC`, kill the `quickshell` instance running `tour-banner.qml` and `imv` (by process ID, `pgrep -f tour-banner`), and restore by hand what the tour changed.
- **The Proceed button does nothing**: a click needs the pointer to have moved onto the button first, as a real mouse does. If you are driving it with `ydotool` yourself, move onto the button, then click.
- **The GIF is too big**: shorten the tour, lower the frame rate or width, or reduce `max_colors` in the last `ffmpeg` command of `scripts/tour.sh`.
- **The apps open on your real screen instead of the virtual one**: the window that asks puts focus on your real monitor; the recorder refocuses the virtual one after it appears. If you add steps that open windows before `tour_play`, refocus it yourself: `hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })"`.
- **A "Process crashed: xdg-desktop-portal-hyprland" notice** (in `--nested` mode): a portal started inside the nested session and died when its compositor went. The recorder now gives the nested session a D-Bus that starts nothing by itself and stops its processes before the compositor, so this should not appear; if it does, `coredumpctl list` shows which process, and the notice (critical, so it stays up) can be cleared with `omarchy-notification-dismiss "Process crashed"`.
- **Your pointer jumped**: it is on the virtual monitor for the length of the tour, and goes back to where it was at the end.

## Human-like input

People do not move a mouse in straight lines at a steady speed or type at metronome intervals, and a GIF of a robot looks fake. By default (`TOUR_HUMAN=1`) the recorder moves and types the way the research and the existing emulators describe. `TOUR_HUMAN=0` gives plain, even motion; `TOUR_SEED=N` makes the randomness repeatable for a run you want to reproduce.

**The pointer** (`glide`, `click`, `drag` in `scripts/tour.sh`, `scripts/nested/vptr.c`):

| What a person does | How it is modelled | From |
|---|---|---|
| Longer or smaller targets take longer | Movement time = 0.15 + 0.12 · log2(distance / 40 + 1) seconds, so a 100 px move takes about 0.3 s and a 1,100 px move about 0.9 s. The constants are typical mouse values I chose, not measurements of anyone | Fitts's law |
| Starts slowly, is fastest in the middle, arrives slowly | The position follows the minimum-jerk curve 10t³ − 15t⁴ + 6t⁵ | Flash & Hogan 1985 |
| A gently curved route, not an S | A cubic Bézier whose two control points are on the same side of the straight line, at most about 15 px off it | [ghost-cursor](https://github.com/Xetera/ghost-cursor) |
| Drifts a little as the hand moves | Correlated noise like WindMouse's "wind": each step's wind is the last one divided by √3 plus a small random kick, fading out near the target | [WindMouse](https://windmouse.readthedocs.io/en/latest/algorithm.html) |
| Overshoots a far target and corrects | A move over 500 px overshoots by 2 to 5 px in about 30% of cases, then settles back in three small steps (500 px is ghost-cursor's `overshootThreshold`) | ghost-cursor |
| Does not hit the exact pixel | The pointer settles within 2 px of the target, and clicks where it is | ghost-cursor (random point in the element) |
| Rests before clicking | A random 0.15 to 0.45 s pause | |

**Typing** (`type_chars`): one key at a time, each gap drawn from a **log-normal** distribution (median 118 ms, so a mean near 130 to 140 ms, like a fairly fast typist), never below about 60 ms, a little quicker when the next key is under the other hand (about 7%), a little slower when it is under the same hand (about 6%), and 35% slower after a space, where a person reads ahead. In a test of 408 gaps this gave a mean of 138 ms, a median of 123, a minimum of 64 and a skewness of 1.7. Those figures come from the study the model is built on:

- Dhakal, Feit, Kristensson and Oulasvirta, **["Observations on Typing from 136 Million Keystrokes"](https://userinterfaces.aalto.fi/136Mkeystrokes/)**, CHI 2018 ([paper](https://www.pokristensson.com/pubs/DhakalEtAlCHI2018.pdf)). Their 168,000 typists averaged 51.6 words per minute and a **mean inter-key interval of 238.7 ms (SD 111.6) with a lower bound near 60 ms**; the distribution is right-skewed (skewness 1.98); fast typists average about 120 ms; key presses last about 116 ms whoever is typing; and hand alternation predicts speed better than repeated letters. The tour deliberately types faster than the average person, so it reads well in a GIF.

**Not modelled** (so you know the limits): typing mistakes and corrections, key rollover (pressing the next key before releasing the last, which the study found in 25% of keystrokes), key-press duration, pauses to think, and a pointer that wanders while "resting". A step that waits (`sleep`) still waits exactly that long.

## Reading time

A caption that vanishes before it can be read is useless, and a viewer reads a new caption before looking at what the pointer does. Both are modelled from reading research, and both can be tuned:

| What | Rule | Default |
|---|---|---|
| **How long a caption stays up** (`TOUR_READ_WPM`) | Held at least 0.95 s (to notice it, plus the 0.15 s gap before the next) plus its words at 150 words a minute, and never under 2.5 s. A 10-word caption is up at least 5 s; a 14-word one 6.5 s. The tour waits out what is missing before the next caption. `0` turns it off | 150 |
| **How long the pointer waits before it moves** (`TOUR_LEAD_WPM`) | The first pointer or key action after a caption waits 0.5 s plus the caption's words at 238 words a minute (a little different each time, ×0.9 to ×1.2): about 3 s for 10 words. Opening a window is not input, so it appears with the caption and there is something to look at while reading. `0` turns it off | 238 |

The numbers come from:

- Brysbaert, **["How many words do we read per minute? A review and meta-analysis of reading rate"](https://www.gwern.net/doc/psychology/linguistics/2019-brysbaert.pdf)**, *Journal of Memory and Language*, 2019: 190 studies and 18,573 participants give an average silent reading rate for English adults of **238 words a minute** for non-fiction (260 for fiction), with most adults between 175 and 300; children, older adults and people reading in a second language are slower. The *lead* uses the average, the *hold* uses 150, well below the slow end, because a viewer is also following a moving picture.
- **Subtitle standards**, the closest everyday case of short text on a moving picture: the BBC's are described as 160 to 180 words a minute and Netflix's English guide as at most 20 characters a second for adults (17 for children), with a minimum of about 0.83 s per subtitle. I read these from secondary summaries ([Nimdzi](https://www.nimdzi.com/speed-in-audiovisual-translation/), [Titlevision](https://titlevision.dk/sm/reading_speed.htm)), not from the guides themselves, so check the current guides if you depend on the exact figures.

The tour prints the result for each caption (`tour: caption 3 (4 words) on screen 4.3 s (reading time 2.5 s)`), so you can see that every caption was up long enough. Reading time is why the StartAppImage tour is about 75 seconds and not 50.

## Nested mode (`--nested`)

The default mode films a hidden virtual monitor and drives your **real** mouse and keyboard, so you cannot use them while it runs, and it changes your real app and settings and puts them back afterwards. `--nested` removes all three problems:

```sh
scripts/hero.sh --nested             # or: scripts/tour.sh TOURFILE --nested
```

- **You can cancel it.** The red strip has a **Cancel recording** button. It is above the shielded window, so you can click it while you cannot touch the recording. It stops the tour at once (within a step), throws the sandbox away, and turns the strip grey with "Recording cancelled"; nothing is kept and nothing of yours was changed. Ctrl+C in the terminal does the same. (The default virtual-monitor mode has no such button: the pointer is on the other screen there. Ctrl+C in the terminal is the way out, and it puts everything back.)
- **You can watch it.** The tour runs inside a **second Hyprland that opens as a window** on your screen (1280×800, centred, a red status strip above it saying what step it is on). In it is a **second Omarchy shell** with your real bar layout and the theme's wallpaper, so it looks like your desktop, with only this app's plugin loaded.
- **Your mouse and keyboard cannot reach it.** A transparent shield window covers the nested window (your clicks and hovers land on the shield and do nothing, with a "forbidden" pointer), and the window is never given the keyboard. The tour itself is driven over the nested session's own Wayland socket: a *virtual pointer* (`scripts/nested/vptr`, a small C client built for each run) and a *virtual keyboard* (`wtype`). Nothing it does moves your pointer or types into your windows, and you can carry on working in other windows, though not in the nested one.
- **It changes nothing of yours.** The nested session has a **sandbox home** with *copies* of what the tour file lists, a minimal `shell.json` that loads only this plugin (linked to your checkout, so it shows the code you are working on), and read-only links to your themes. Settings, apps and files the tour changes are the sandbox's copies, thrown away at the end. `tour_restore` is not run, and no shell restart is needed.
- **Nothing is left behind.** At the end everything the nested session started (its compositor, shell, its own D-Bus, file watchers) is stopped, and the window closes. The nested session has a D-Bus of its own that starts nothing by itself, so it does not launch portals that would crash and make Omarchy show you a crash notice.

### Extra requirements

`Hyprland` (you are in it), `dbus-run-session`, `wtype`, and `gcc`, `wayland-scanner` and `pkg-config` with the Wayland client library (to build the pointer client; Arch: `wayland`, `wayland-protocols`, `gcc`). The monitor needs about 1,050 pixels of height: the nested window is 1280×800 and goes below the status strip (24 px gap, 170 px high), its own title bar (30 px) and a 10 px margin, so it starts 234 px from the top. These are worked out from the strip's size in `scripts/nested/session.sh`, and the strip reads its size from the same place, so they cannot drift apart. If the monitor is too short the recorder says by how much the two will overlap. The recorder checks and says what is missing.

### What a tour file adds for `--nested`

| Variable / function | Meaning |
|---|---|
| `TOUR_PLUGIN_ID` | **Required.** The plugin's id, to load in the sandbox. |
| `TOUR_SANDBOX_COPY=(path …)` | Paths under `$HOME` to *copy* into the sandbox, the data the tour changes (e.g. `.local/share/startappimage`). |
| `TOUR_SANDBOX_LINK=(path …)` | Paths under `$HOME` to *link* read-only (e.g. icons). |
| `tour_sandbox DIR` | Optional. Runs with the sandbox home to adjust the copies, e.g. give an app its own copy of a file that the tour will overwrite. |
| `TOUR_BACKDROP=plain` | Put the flat `TOUR_BG` colour over the wallpaper, as the virtual monitor mode does. Default: the theme's wallpaper. |

Differences in a tour file:

- **`$HOME` is the sandbox** while `tour_prepare`, `tour_setup` and `tour_play` run, and `omarchy-shell`, `hyprctl` and `grim` act on the nested session. A tour file therefore has to work out paths when it uses them (`$HOME/…` inside a function), not when the file loads, or it will point at your real files. `tour_requires` still runs with your real home, before the sandbox exists.
- **`key` is not available**: use `esc` and `typed`. (`wtype` types text and presses named keys; `esc` is Escape.)
- **Coordinates** are the nested monitor's: `0,0` at its top-left, 1280×800. The bar is the real one, so it is as tall as yours.

### What I know does not work or is untested

- A first run builds the pointer client; if the build fails the recorder stops with that message.
- Several monitors: the window and the status strip go on the monitor that was focused when you started. Not tested with more than one.
- The nested session is Hyprland-in-Hyprland. A compositor that is not Hyprland, or a Hyprland that changes its Lua configuration API, will need changes in `scripts/nested/session.sh`.
- **Open issue, default mode:** a virtual-monitor run started right after a `--nested` run has sometimes recorded nothing (the app's window did not open; running again worked). The virtual-monitor code did not change and two virtual runs in a row are fine, but I have not found the cause. If you see a ~30 KB GIF, run it again.
- In the install card the sandbox's home folder shows as its full path (`/home/you/Applications`) instead of `~/Applications`, because `$HOME` differs.

## Using it in another Start app

The recorder has no StartAppImage in it. To use it for another app:

1. Copy `scripts/tour.sh` into the app's repo (it will live in a shared repository when the Start apps get one, see "Shared UI code" in [ui-standards.md](ui-standards.md)).
2. Write the app's tour file in its `scripts/tours/` (start from the minimal tour above, and copy `scripts/tours/hero.sh` for a worked example with `tour_prepare` and `tour_restore`).
3. Set `TOUR_TITLE`, `TOUR_OUT` and `TOUR_LAYER`, find the coordinates, and run it without `--install` until it reads well.
4. Add `screenshots/hero.gif` (or wherever `TOUR_OUT` points) to the app's README, and a line to its contributing notes about retaking it.
