# Repo Skills Profile

This file pairs with `.codex/skills/index.json`. It carries the human-readable
evidence summary that the routing index points at: caveats, scoped patterns,
evidence gaps, and any rules the validator should warn about.

This is a stub. Run the `derive-repo-skills` workflow against this repo to
populate it:

```
/analyze derive repo skills
```

or invoke the skill directly. See `~/.agents/skills/derive-repo-skills/SKILL.md`
for the full workflow.

## Sections (populated by derive-repo-skills)

### Coverage

What the index covers (paths, modules, languages) and what it intentionally
excludes.

### Confirmed patterns

Repo-local patterns the workflow saw evidence for in 2+ files. These are the
load-bearing routing signals consumers should trust.

### Single-evidence patterns

One-off patterns. Consumers should treat these as suggestions, not rules.

### Evidence gaps

Places where the workflow expected a pattern but couldn't confirm it.
Useful for the next derive run.

### Caveats

Per-skill caveats — known false-positive directions, scope boundaries,
or "do not load this skill for X" rules.
