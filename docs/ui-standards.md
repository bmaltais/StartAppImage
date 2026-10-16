# UI standards

How StartAppImage looks and behaves, and where it differs from the other Start apps. **The shared rules are in the devkit: [scripts/devkit/docs/ui-standards.md](../scripts/devkit/docs/ui-standards.md)** (principles, window and card rules, moving and resizing, remembered state, the settings window's layout, applying settings, controls, shared words, notifications). Read it first. This file holds only what is StartAppImage's own, and its decision log.

**Both files are the source of truth for the UI.** Read them before you change anything visible. If a change makes a design decision that is not covered, or goes against something that is, update the right file in the same change (this one for this app, the kit's for something shared) and add a line to the [decision log](#decision-log) here. A UI change without a matching update is not finished.

Sizes are written the way the code writes them: `space(n)` is `Style.space(n)`. Never hard-code pixels, colours or fonts.

## Where StartAppImage differs from the shared rules

- **A failed setting is always a critical notification.** The kit says a failure is shown under the setting where the window can show it, otherwise as a critical notification. The main settings window sends the notification ("Setting was not applied" and the reason) for every failed setting and flips the control back on the read-back. An app's own settings show a red line under the setting the error is about instead (see [App settings](#app-settings)).
- **Closing a settings window returns keyboard focus to the manager's search box**, not just to the manager.
- **The install card replaces the manager** rather than floating over it (see below).

## Windows

The manager and the settings window follow the kit's sizes and rules. Remembered size and position are `WIN_*` (manager) and `SETUP_*` (settings window) in `~/.config/startappimage/config`, read with `startappimage window`. This app adds:

| Card | Width | Height | Moves | Resizes | Closes with |
|---|---|---|---|---|---|
| App settings window | the settings window's | the settings window's | yes (same place as the settings window) | yes (same size) | Esc, ✕, click outside or on the dimmed manager |
| Install card | 520 | its content | no | no | Esc, ✕, Cancel |

- **Settings windows.** The main settings window and an app's settings window share one size and position, so opening either puts the window in the same place. Only one is open at a time.
- **Install card.** It replaces the manager instead of floating over it.
- **Drop target.** An `.AppImage` dropped on any card opens the install card.

## Settings windows

`SetupView.qml` (the main settings) and `SettingsView.qml` (one app's) are the thin files around `SettingsWindow.qml`. The window name is "StartAppImage" with "SETTINGS" under it; for an app, its icon and name with "SETTINGS · 0.8.0" (its version).

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

Queueing, read-back and the first run are the kit's. What is this app's:

- **Reset to defaults** applies: launcher, file handler and command line on, bar icon off, checks every 6 hours, size and position remembered. These values are the CLI's (`defaults` in `startappimage integration`), not written here or in the QML.
- **A failed change** is a critical notification; see [Where StartAppImage differs](#where-startappimage-differs-from-the-shared-rules).

## Words

This app's vocabulary, on top of the kit's:

- **Names.** *AppImage* is one word, capitalised that way. The window is the **manager**; the other window is the **settings window**. A single app's card is its **settings**.
- **Verbs.** *Install AppImage…* (not Add), *Uninstall*, *Update*, *Open*, *Reset to defaults*.
- **Search boxes.** "Search installed AppImages" in the manager, "Find a setting" in the settings window.

## The manager

- **Header.** App icon, the name, a count line in small capitals ("7 INSTALLED"), then two buttons: settings (gear) and check for updates (spinning while it runs). The close button is in the corner.
- **Search.** A full-width pill under the header. The manager's search box is focused whenever the manager is shown or returns to the front.
- **List.** One row per app (62 high, 8 apart): icon, name, `EXTERNAL` tag when installed by something else, version and source, then open, settings and uninstall. The row under the keyboard cursor has an accent border. An update shows as an accent dot and "Update available a > b" with an **Update** button; the header gains **Update all**.
- **Footer.** **Install AppImage…** on the left, "Esc to close" on the right, and the resize grip in the corner. Choosing Install opens a row with one field that takes a path, a download URL, `github:owner/repo` or a github.com link.
- **Keyboard.** Type to search; Up and Down move; Enter opens; Ctrl+U updates; Delete uninstalls (after a confirmation); Esc clears the search, then closes.

## The bar icon

The glyph is the download-arrow, at the end of the right section of the bar. Right click checks for updates. It turns accent-coloured while an update is waiting, read from `~/.cache/startappimage/updates`, which every update check writes.

**Off by default here.** Some people want a way in from the bar; most do not (see the decision log). StartDrive turns it on by default; that is StartDrive's own decision, recorded in its `ui-standards.md`.

## Notifications

- **Update available.** A system notification with **Update** and **Open manager** actions, shown once per new version, and not while the manager is open.
- **Setting failed.** A critical notification; see [Where StartAppImage differs](#where-startappimage-differs-from-the-shared-rules).

## Verifying a UI change

A change is done once it has been seen working in `scripts/dev` ([testing.md](testing.md)). Retake the README screenshots with `scripts/screenshots.sh` when the look changes, and the tour when a step of it changes ([recording-tours.md](recording-tours.md)).

## Shared UI code

**StartAppImage is the reference implementation of the shared components** (the controls, `SettingsWindow`, the drag-and-resize behaviour): StartDrive's copies are kept identical to this app's. What is shared and what is not yet is in [scripts/devkit/docs/ui-standards.md](../scripts/devkit/docs/ui-standards.md#shared-ui-code). StartBar's settings window is the reference design.

## Decision log

Newest first. One line each: what was decided, and why.

| Date | Decision | Why |
|---|---|---|
| 2026-10-15 | UI changes are tested in a nested session (`scripts/dev`), not on the real desktop | Clicks and restarts on the real shell moved the maintainer's pointer and typed into their windows; see [testing.md](testing.md) |
| 2026-10-15 | After an update succeeds the app is dropped from the "updates waiting" list at once | The row flashed "Update available" again for about a second until the next check finished, which looked like the click had not worked |
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
| 2026-10-15 | A setting error is shown next to the setting the CLI names (`field`), and an app's source label comes from the CLI's `sourceKind` and `repo` | Matching the wording of an error, or the `github:` prefix, broke silently when a message changed |
| 2026-10-15 | Defaults for Reset and "Enable recommended" come from the CLI's `integration` | The same defaults were written in the CLI, the service and the view |
| 2026-10-15 | "Another folder" is checked as you type by the CLI (`startappimage folder`), not by a rule copied into the view | The home-folder rule lived in the CLI and the view and could drift |
