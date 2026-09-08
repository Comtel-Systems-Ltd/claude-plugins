# Comtel Systems — Claude Code Plugins

Claude Code plugin marketplace for Comtel Systems engineering skills.

## Install

```
/plugin marketplace add <github-owner>/claude-plugins
/plugin install comtel@comtel-systems
/plugin install claude-taskbar@comtel-systems   # Windows only
```

Skills become available namespaced, e.g. `/comtel:diptrace`.

## Contents

| Skill | Purpose |
|-------|---------|
| `diptrace` | Read DipTrace schematics: KiCad netlist (`.net`) workflow, `.asc`/XML parsers, format gotchas. See its `SKILL.md`. |
| `real-work` | Durable, resumable plan artifacts: phases, per-item checkboxes, verification, handoff summary. |

## claude-taskbar (Windows)

Gives the Windows Terminal window hosting a Claude Code session its own taskbar
button with the Claude logo while the session runs. A `SessionStart` hook, no
configuration. See `plugins/claude-taskbar/README.md`.

## Statusline

`statusline/` holds the custom Claude Code statusline (model · context · effort · path · git · caveman badge).
Not part of the plugin — install per machine:

```powershell
.\statusline\install.ps1
```

See `statusline/README.md`.

## Updating

Edit under `plugins/comtel/skills/`, commit, push. Plugins version by commit — reinstall/update picks up the latest.

## Adding a skill

1. Create `plugins/comtel/skills/<name>/SKILL.md` (frontmatter: `name`, `description`).
2. Helper files live in the same folder.
3. Commit + push. Available as `/comtel:<name>`.
