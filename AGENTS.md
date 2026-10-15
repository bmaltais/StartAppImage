## Agent skills

### Issue tracker

Issues live in GitHub Issues (`bmaltais/StartAppImage`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Testing

- **`scripts/dev`**: test every UI change in the nested test session, out of reach of the user's pointer and keyboard. `scripts/dev up`, then `open`, `shot FILE` (look at it), `click PX PY`, `type TEXT`, `key NAME`, `errors` (0 = clean). After an edit, `scripts/dev reload` (4 s, loads uncommitted files). Finish with `scripts/dev down`. `scripts/dev --help` lists the rest.
- **`scripts/check.sh`**: lint, qmllint, manifest. Runs in the pre-commit hook (`git config core.hooksPath .githooks`); commits go on a branch, never `main`.
- **`scripts/reload`, `scripts/pointer.sh`**: the user's real shell and pointer. Use them when the user asks to see it there; ask first.
- Full guide, with `scripts/sheet` and what went wrong before: `docs/testing.md`.

## UI standards

`docs/ui-standards.md` says how the UI looks and behaves and why. Follow it for any visible change. When a change makes a design decision, or goes against what it says, update that file in the same change and add a line to its decision log. UI work is done once seen working in `scripts/dev`.

Reference for the settings window: StartBar, `~/.config/omarchy/plugins/io.github.bmaltais.startbar` (`Service.qml`, `ScrollTrack.qml`, `scripts/pointer.sh`, `scripts/smoke.sh`).

## Recorder

`docs/recording-tours.md` before changing `scripts/tour.sh`, `scripts/tours/`, `scripts/tour-banner.qml` or `scripts/nested/`.
