## Agent skills

### Issue tracker

Issues live in GitHub Issues (`bmaltais/StartAppImage`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Before calling work done

Always restart the plugin so the running shell loads your changes, and check it in the real app, before saying the work is done. The installed plugin is a separate clone at `~/.config/omarchy/plugins/io.github.bmaltais.startappimage`: make sure it is on the branch you changed, then run `omarchy plugin disable io.github.bmaltais.startappimage && omarchy plugin enable io.github.bmaltais.startappimage`. Say so plainly if you could not restart or test it.
