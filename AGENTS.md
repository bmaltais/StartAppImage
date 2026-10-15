## Agent skills

### Issue tracker

Issues live in GitHub Issues (`bmaltais/StartAppImage`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## UI standards

`docs/ui-standards.md` says how the UI looks and behaves and why: windows, the settings window, controls, wording, and how to verify a change. Follow it for any visible change. When a change makes a design decision, or goes against what it says, update that file in the same change and add a line to its decision log. Do not call UI work done without that.

## Before calling work done

Always restart the plugin so the running shell loads your changes, and check it in the real app, before saying the work is done. The installed plugin is a separate clone at `~/.config/omarchy/plugins/io.github.bmaltais.startappimage`: make sure it is on the branch you changed, then run `omarchy-restart-shell` (the bar blinks for a moment). `omarchy plugin disable` then `enable`, and the shell's own "Local plugin changed, reloading" message, did NOT load new QML: the running shell kept the old files until the full restart. Then open the manager with `omarchy-shell io.github.bmaltais.startappimage open` (it toggles, so check the state) and take a `grim` screenshot to look at it. Say so plainly if you could not restart or test it.
