# Comtel Systems — Claude Code Plugins

Claude Code plugin marketplace for Comtel Systems engineering skills.

## Install

```
/plugin marketplace add <github-owner>/claude-plugins
/plugin install comtel@comtel-systems
```

Skills become available namespaced, e.g. `/comtel:diptrace`.

## Contents

| Skill | Purpose |
|-------|---------|
| `diptrace` | Read DipTrace schematics: KiCad netlist (`.net`) workflow, `.asc`/XML parsers, format gotchas. See its `SKILL.md`. |

## Updating

Edit under `plugins/comtel/skills/`, commit, push. Plugins version by commit — reinstall/update picks up the latest.

## Adding a skill

1. Create `plugins/comtel/skills/<name>/SKILL.md` (frontmatter: `name`, `description`).
2. Helper files live in the same folder.
3. Commit + push. Available as `/comtel:<name>`.
