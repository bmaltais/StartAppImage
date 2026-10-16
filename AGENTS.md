## Agent skills

### Issue tracker

Issues live in GitHub Issues (`bmaltais/StartAppImage`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Testing

- **`scripts/dev`**: test every UI change in the nested test session, out of reach of the user's pointer and keyboard. `scripts/dev up`, then `open`, `shot FILE` (look at it), `click PX PY`, `type TEXT`, `key NAME`, `errors` (0 = clean). After an edit, `scripts/dev reload` (4 s, loads uncommitted files). Finish with `scripts/dev down`. `scripts/dev --help` lists the rest. The session runs behind a guard that refuses power commands, so a click on one there does nothing.
- **`scripts/check.sh`**: the devkit's `check` (shellcheck, qmllint, manifest) plus `tests/cli.sh` and the icon check from `devkit.conf`. Runs in the pre-commit hook (`scripts/devkit/bin/pre-commit --install`); commits go on a branch, never `main`.
- **`scripts/reload`, `scripts/pointer`**: the devkit's, for the user's real shell and pointer. Use them when the user asks to see it there; ask first. The plugin is installed as a git clone, so `reload` needs the branch pushed.
- Full guide, with `scripts/sheet` and what went wrong before: `docs/testing.md`.

## UI standards

The shared UI rules (principles, windows, settings window, controls, words) are in `scripts/devkit/docs/ui-standards.md`; `docs/ui-standards.md` holds where StartAppImage differs, its own windows, settings and words, and the decision log. Follow both for any visible change. When a change makes a design decision, or goes against what they say, update the right file in the same change (this app's for this app, the devkit's for something shared, in that repository, since `scripts/devkit` is not edited here) and add a line to the decision log in `docs/ui-standards.md`. UI work is done once seen working in `scripts/dev`.

Reference for the settings window: StartBar, `~/.config/omarchy/plugins/io.github.bmaltais.startbar` (`Service.qml`, `ScrollTrack.qml`, `scripts/smoke.sh`).

## Recorder

`docs/recording-tours.md` (this app's tour; the rest is `scripts/devkit/docs/recording-tours.md`) before changing `scripts/tours/` or `devkit.conf`. The session and recorder themselves are the shared devkit's (`scripts/devkit`, a git submodule of `bmaltais/omarchy-plugin-devkit`, so it is not in what users install or what the marketplace reviews; clone with `--recurse-submodules`, or `git submodule update --init`): fix a bug there in that repository, release it, and move the pointer (`git -C scripts/devkit checkout vX.Y.Z`, then commit); do not edit the files here.
