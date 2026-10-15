# UI standards

How StartAppImage looks and behaves, and why. The goal is that it feels like the rest of the Start family (StartBar, StartDrive) and like Omarchy itself, so a person who knows one knows them all.

**This file is the source of truth for the UI.** Read it before you change anything visible. If a change makes a design decision that is not covered here, or goes against something that is, update this file in the same change and add a line to the [decision log](#decision-log). A UI change without a matching update here is not finished.

Sizes are written the way the code writes them: `space(n)` is `Style.space(n)`, which follows the user's font and spacing scale. Never hard-code pixels, colours or fonts.

## Principles

1. **Follow the theme, always.** Colours, fonts, corner radius and spacing come from the shell (`Color`, `Style`, `Util.alpha`). Nothing is hard-coded, so the UI follows the Omarchy theme live. Muted text is the foreground at about 55% opacity, hairlines about 14%.
2. **Same as StartBar where they overlap.** The settings window copies StartBar's settings window. When StartBar and this file disagree, ask which is right and fix the other one.
3. **Changes happen when you make them.** No Apply buttons for settings (see [Settings window](#settings-window)). A change that cannot be made says so and goes back.
4. **The window you came from stays.** A window opened from another one floats over it; closing it brings the first back.
5. **Everything in the UI has a command-line equivalent.** The QML never edits files; it asks `bin/startappimage`. A setting that exists in the window exists as a `setup` option.
6. **Say what will happen.** Every setting has a one-line hint, written as what the setting does, in the present tense.
7. **Quiet by default.** Destructive or rarely used actions are soft pills, not primary buttons. Colour (accent) is for the one thing to do and for the selected state.

## Windows

Every window is a card on a full-screen layer-shell overlay with a dimmed scrim. The card has the menu background, a hairline border at 14% foreground, the theme radius and a soft shadow.

| Card | Width | Height | Moves | Resizes | Closes with |
|---|---|---|---|---|---|
| Manager | 640 (or the user's) | content, up to 580 and the screen minus 80 | yes | yes | Esc, ✕, click outside |
| Settings window | 760 (or the user's) | 520 (or the user's), at most the screen minus 80 | yes | yes | Esc, ✕, click outside or on the dimmed manager |
| App settings window | the settings window's | the settings window's | yes (same place as the settings window) | yes (same size) | Esc, ✕, click outside or on the dimmed manager |
| Install card | 520 | its content | no | no | Esc, ✕, Cancel |

- **Dismissing.** Esc closes only the topmost window. In a search box, Esc clears the text first. A click on the scrim closes the topmost window.
- **Stacking.** The settings window and an app's settings window float over the manager, which stays visible behind them under a 35% dark veil. Only one of them is open at a time. Closing one returns focus to the manager's search box. The install card still replaces the manager.
- **Opening.** The manager opens where the user last left it (see [Remembered state](#remembered-state)).
- **Close button.** A ✕ in the top-right corner of every card, 8 from the edges.
- **Drop target.** An `.AppImage` dropped on any card opens the install card.

### Moving and resizing (manager and settings window)

- **Move** by dragging the top strip of the card, 60 high, whatever is not a control. The pointer is an open hand over it and a closed hand while dragging. Controls in the strip (search box, buttons) keep their own behaviour.
- **Resize** from the bottom-right corner: a 22 square handle with a small two-line grip and the diagonal resize pointer. The top-left corner stays put. Double-click it to go back to the default size and centre.
- **Limits.** The manager is at least 480 by 300, the settings window 560 by 360, both at most the screen minus 40. At least a 60 strip of the card always stays on screen.
- **Maths.** A card is centred plus an offset, so a resize shifts the centre by half the change.

### Remembered state

Size and position of each window are saved in `~/.config/startappimage/config` (`WIN_*` for the manager, `SETUP_*` for the settings window) and restored on the next open, even after a shell restart. Two switches control it, under **Window**: *Remember size* and *Remember position*. Switching one off forgets the saved value and opens centred, at the default size. They are read with `startappimage window` and written when a drag or resize ends.

## Settings windows

There are two, the main one and one per app, and they are the same component: `SettingsWindow.qml` draws the header, page list, rows and footer; `SetupView.qml` (the main settings) and `SettingsView.qml` (one app's) only say what the pages and settings are. A new settings window is a new thin file around `SettingsWindow`, never a new layout. They share one size and position, so opening either puts the window in the same place.

Modelled on StartBar's settings window.

```
┌──────────────────────────────────────────────────────────┐
│                  ( 🔍 Find a setting )                  ✕ │  header, 60
│ StartAppImage │ General                                   │
│ SETTINGS      │                                           │
│ ▌General      │ App launcher entry              [●━]      │
│  Bar          │ hint…                                     │  rows
│  Updates      │ ───────────────────────────────────────── │
│  Window       │ Open .AppImage files with  [A][B]         │
│               │ ─────────────────────────────────────────  │
│ ───────────────────────────────────────────────────────── │
│ Changes apply instantly · Esc to close   [Reset to defaults] ◢│  footer, 52
└──────────────────────────────────────────────────────────┘
```

- **Header (60).** A centred search pill, "Find a setting", with the magnifier glyph. While there is text, the right side lists matching settings from every page under "Search results", each group headed by its page name. No match says "No setting matches “…”."
- **Page list (190 wide, left).** The window name in bold with a small-caps line under it that says what the window is for: "SETTINGS" (and for an app, "SETTINGS · 0.8.0" with its version), the same title-over-small-caps pattern as the manager's "7 INSTALLED". Then one 38 high row per page. The title block and the page heading beside it are 48 high. The current page has a 22% accent fill and a 3 wide accent mark on the left, and bold text. Hover is the shell's hover fill. A click clears any search.
- **Heading.** The page name, body size + 8, bold, on the row of the window name.
- **Body.** Scrolls when the page is taller than the window, with the [scroll bar](#controls) in a gutter that is always reserved, so the width never changes.
- **Setting row.** The label (body size) with its hint under it (caption size, 55% opacity), the control on the right, a hairline at 50% under each row. The row is as tall as its label plus hint, with 6 above and below.
- **Disabled setting.** Dimmed to 40%, not clickable, and the hint says why (for example, the command-line link when another file is at that path).
- **Footer (52).** A hairline above it. On the left one muted line: "Changes apply instantly · Esc to close". On the right one pill, 30 clear of the resize grip.

### Pages and settings

| Page | Setting | Control | Option for `setup` |
|---|---|---|---|
| General | App launcher entry | switch | `--launcher` |
| General | Open .AppImage files with | choice: StartAppImage / Leave as is (or Keep *X*) | `--handler` |
| General | Command line | switch | `--cli` |
| Bar | Bar icon | switch | `--bar-icon` |
| Updates | Check for updates | choice: Hourly, 6 hours, Daily, Weekly, Never | `--check-hours` |
| Window | Remember size | switch | `--remember-size` |
| Window | Remember position | switch | `--remember-position` |

A new setting goes on the page it belongs to, or a new page if none fits. Add it to the `pages` list in `SetupView.qml` (label, hint, control, key) and to `flags`, add the `setup` option, add it to `integration`, and add a row to this table.

### App settings

The window title is the app's icon and name, with "SETTINGS · version" under it. Pages and settings:

| Page | Setting | Control | Applies with |
|---|---|---|---|
| General | Name | text, under its label | `set --name`, on Enter or when the box loses focus |
| General | Show in the app launcher | switch | `set --hidden` |
| General | Launch options | text | `set --args` |
| Updates | Source | text with a live preview | `set --source` |
| Location | Folder | choice of the known folders, wrapping | `set --dir` (moves the file) |
| Location | Another folder | text, checked as you type | `set --dir`, on Enter |

- **Source** takes any GitHub link form. After a short pause it shows `✓ owner/repo · latest vX`, the AppImage it would pick for this CPU and how often it is checked, or says why not ("Checking…", no AppImage for this CPU, not found). A source that fails the check is not saved; one saved while GitHub is unreachable says so. Pressing Enter before the check finishes waits for it. Empty means "not updated automatically".
- **Another folder** says "That looks like a link, not a folder" when a link is pasted, and rejects folders outside the home directory, before anything is saved.
- **Errors** from `set` appear as a red line under the setting they are about. A failed change does not close the window.
- **Esc** drops what is typed in a text box and then closes the window: leaving never saves.
- An app installed outside StartAppImage says so under Name; its changes edit that app's own launcher entry.

### Applying settings

- **Instantly.** Each click runs `startappimage setup` for that one setting. Clicks queue and run one at a time, in order.
- **Read back.** When the queue is empty the window reads the real state back, so a switch always shows what the system has.
- **Failure.** A change that fails is announced with a critical notification ("Setting was not applied" and the reason) and its control flips back on the read-back.
- **Window stays open.** Applying never closes the window.
- **Reset to defaults.** A soft pill. The first click turns it red and asks "Click again to reset everything" for 3 seconds; the second click applies the defaults: launcher, file handler and command line on, bar icon off, checks every 6 hours, size and position remembered.
- **First run.** The window opens once, a few seconds after the plugin first loads, showing what is on now (usually nothing). The footer has **Not now** and an accent-filled **Enable recommended**. After the first change or **Not now** it never opens by itself again.

## Controls

All are inline components or small files in this repo and use only theme tokens.

| Control | Look | Used for |
|---|---|---|
| **Switch** | 42 × 24 pill; accent when on, 25% foreground when off; round knob in the menu background, 3 inset; the knob slides 100 ms, but not while the page is first shown | on/off settings |
| **Choice** | Row of segments 28 high, 2 apart; selected is accent-filled with menu-background text, others 8% foreground; caption size. With many or long options (`stacked`) the segments wrap across the full width under the label, 6 apart | one of a few or several options |
| **Chip** | Bordered rounded box; selected has a 18% accent fill and an accent border | picking a folder, Shown/Hidden in the per-app card |
| **Field** | Single-line text box, 34 high, 6% foreground fill, border brightens on focus. In a settings window it sits under its label at full width and commits on Enter or when it loses focus; Esc drops the edit | text input |
| **Pill** | 32 high, 8% foreground fill, hover fill, caption size; `primary` is accent-filled and bold; `danger` is 50% red | footer actions |
| **Button** | The shell's `Button`; bordered for secondary, selected for primary | dialogs and rows |
| **Scroll bar** (`ScrollTrack`) | 6 wide, soft track at 8%, rounded thumb at 28% that brightens on hover and press; drag the thumb or click the track; shown only when the list overflows | long lists and pages |

Rules of thumb: one accent-filled thing per screen; selected means accent; hover is the shell's hover fill; nothing animates longer than 160 ms.

## Words

- **Case.** Sentence case for labels and hints. Page names are one word where possible.
- **Names.** *AppImage* is one word, capitalised that way. The window is the **manager**; the other window is the **settings window**. A single app's card is its **settings**.
- **Verbs.** *Install AppImage…* (not Add), *Uninstall*, *Update*, *Open*, *Reset to defaults*. A trailing ellipsis only when the action asks for more input.
- **Search boxes.** "Search installed AppImages" in the manager, "Find a setting" in the settings window.
- **Hints.** One or two short sentences, saying what happens. No "please", no exclamation marks.
- **Errors.** Say what happened and what to do. They appear next to what caused them (under the field), or as a notification when the window is gone.
- **Footer hint.** "Esc to close" appears at the bottom of every card that closes with Esc.

## The manager

- **Header.** App icon, the name, a count line in small capitals ("7 INSTALLED"), then two buttons: settings (gear) and check for updates (spinning while it runs). The close button is in the corner.
- **Search.** A full-width pill under the header. The manager's search box is focused whenever the manager is shown or returns to the front.
- **List.** One row per app (62 high, 8 apart): icon, name, `EXTERNAL` tag when installed by something else, version and source, then open, settings and uninstall. The row under the keyboard cursor has an accent border. An update shows as an accent dot and "Update available a > b" with an **Update** button; the header gains **Update all**.
- **Footer.** **Install AppImage…** on the left, "Esc to close" on the right, and the resize grip in the corner. Choosing Install opens a row with one field that takes a path, a download URL, `github:owner/repo` or a github.com link.
- **Keyboard.** Type to search; Up and Down move; Enter opens; Ctrl+U updates; Delete uninstalls (after a confirmation); Esc clears the search, then closes.

## The bar icon

Optional, off by default, switched in the settings window. It is the download-arrow glyph, placed at the end of the right section of the bar. Left click opens or closes the manager (the same command as the launcher entry); right click checks for updates. It turns accent-coloured while an update is waiting, read from `~/.cache/startappimage/updates`, which every update check writes.

## Notifications

- **Update available.** A system notification with **Update** and **Open manager** actions, shown once per new version, and not while the manager is open.
- **Setting failed.** A critical notification, because the settings window cannot show it in place.

## Verifying a UI change

A change is not done until it has been seen working.

1. Commit and push, then `git pull` in the installed plugin (`~/.config/omarchy/plugins/io.github.bmaltais.startappimage`).
2. Run `omarchy-restart-shell`. Plugin reload and `omarchy plugin disable/enable` do **not** load new QML.
3. Open the window (`omarchy-shell io.github.bmaltais.startappimage open` or `setup`; both toggle or show) and take a screenshot with `grim`.
4. Click the real controls with `ydotool` and screenshot again. On a monitor that does not start at x = 0, `ydotool mousemove --absolute` lands at twice the coordinate you give plus the monitor's origin, so check with `hyprctl cursorpos`. Screenshot before each click: a click outside a card closes it.
5. Read the shell log for QML errors: `journalctl --user --since -1min -o cat`.
6. Retake the README screenshots with `scripts/screenshots.sh` when the look changes, retake the tour with `scripts/hero.sh --install` when a step of it changes (see [Recording the tour](#recording-the-tour)), then rebuild `preview.png` (the 1600 by 900 title image) with `scripts/preview.sh`. Both put a plain backdrop behind the cards. Set the manager to about 690 by 696 first (`startappimage window --size 690x696 --offset 0,0`, then restart the shell) so the hero shows every app without a cut-off row, and restore your own window values afterwards.

## Recording the tour

The GIF at the top of the README is a short story of using the app, recorded by `scripts/tour.sh`, a recorder that is **not specific to StartAppImage** (the full guide, with a worked example and troubleshooting, is [recording-tours.md](recording-tours.md)): it films a temporary virtual monitor frame by frame (so your own screen is left alone), puts a plain backdrop on it, clicks through the app with the real pointer and keyboard, adds a caption for each step and writes the GIF. Each app supplies a **tour file** that says what to do; this app's is `scripts/tours/hero.sh`. `scripts/tour.sh TOURFILE [--install]` runs one, and `scripts/hero.sh` is the shortcut for ours.

- **A tour file** is a bash file that sets `TOUR_TITLE` (the app's name), `TOUR_OUT` (the GIF's path), `TOUR_LAYER` (the app window's layer-shell name, so keys and typing are only sent while it is up) and optionally `TOUR_STEPS`, `TOUR_SIZE`, `TOUR_BG` and `TOUR_RESTART_SHELL`; and defines `tour_play` (the steps, using `cap`, `glide`, `click`, `drag`, `typed`, `esc`, `wait_until`) plus, as needed, `tour_requires`, `tour_prepare`, `tour_setup` and `tour_restore`. The header of `scripts/tour.sh` documents the contract; the recorder does the rest, including putting things back if it is interrupted.
- **Story, not a feature list.** Each step is one thing a person does, with a caption that says it in plain words. Ours: double-click an AppImage and see what it is; the manager with an update waiting; one click to update; point an app at its GitHub releases; settings that apply at once; resize and move the window and find it where it was left. About a minute, 10 frames a second, 1200 px wide, a few MB.
- **While it runs** the pointer is on the virtual monitor and typing goes there, so a small banner window in the corner of your real screen says to leave the mouse and keyboard alone, with the step it is on. (Notifications cannot be used for this: they appear on the focused monitor, the virtual one, and would end up in the GIF.) A notification says when it is done.
- **It changes things and puts them back**: whatever the tour's `tour_prepare` saves and `tour_restore` restores. Ours resets the windows' saved size and place, makes one app look a version behind so it can be updated, changes the check interval and switches the bar icon off and on.
- **Keep the tour honest.** It uses the real app, so a step that changes (a button moves, a label is renamed) breaks the tour's clicks: retake and look at the GIF before committing it.

## Shared UI code

The controls above, `SettingsWindow`, the drag-and-resize behaviour and the tour recorder (`scripts/tour.sh`) are meant to be shared by every Start app, so each does not keep its own copy. That is not done yet; the proposal is a shared `StartUI` repository copied into each app (git subtree). Until it exists, this repo is the reference implementation and StartBar's settings window is the reference design.

## Decision log

Newest first. One line each: what was decided, and why.

| Date | Decision | Why |
|---|---|---|
| 2026-10-15 | The README leads with a recorded tour (`screenshots/hero.gif`) made by an app-agnostic recorder that reads a per-app tour file | A still shows a look, not how the app is used; one recorder keeps every Start app's tour alike |
| 2026-10-15 | Settings windows say "SETTINGS" in small caps under their title | Nothing in the window said what it was for; the title-over-small-caps pattern is the one the manager already uses |
| 2026-10-15 | One app's settings use the same `SettingsWindow` as the main settings: pages on the left, applied instantly, floating over the manager, sharing its size and place | Two different looks for "settings" felt inconsistent; one component keeps them identical and is what will move into the shared UI module |
| 2026-10-15 | Settings rows keep their place when the data behind them changes (the models are counts, not arrays) | A live preview rebuilt the list on each keystroke and threw away the text box being typed into |
| 2026-10-15 | Settings window footer: hairline, one hint line on the left, a quiet pill on the right | Reset looked like the main action and "Esc to close" read as a button |
| 2026-10-15 | Settings window and manager are draggable and resizable; sizes and positions remembered, each behind a switch | Matches StartBar; people place windows where they want them |
| 2026-10-15 | The settings window floats over the manager, which stays visible | Opening settings used to remove the manager and not bring it back |
| 2026-10-15 | Settings apply instantly; first run offers "Enable recommended" and "Not now" | Consistency with StartBar; an Apply button hid which row had changed |
| 2026-10-15 | Setup card became a two-pane settings window (pages left, settings right) | The card had grown past what a single column can hold; matches StartBar |
| 2026-10-15 | Optional bar icon, off by default, switched in the settings window | Some people want a way in from the bar; most do not |
| 2026-10-15 | One smart Source field with live preview in the per-app card, placed under the name | A bare "owner/repo" box was misread; people paste links into the wrong field |
| 2026-10-15 | "Install AppImage…" and "Search installed AppImages" | Say what the thing is; "app" was ambiguous next to the app launcher |
| 2026-10-15 | Scroll bar when the list overflows, same style as StartBar's | Long lists were cut off with no hint |
