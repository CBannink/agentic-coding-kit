---
name: skill-import
description: "Use to evaluate and normalize external skill ideas from repositories into lean global kit skills without importing host-specific runtime assumptions or default-agent bloat."
---

# Skill Import

Import ideas, not whole foreign runtimes. External skills should become compact,
lazy global skills under `bundle/global/.agents/skills/<name>/SKILL.md`.

## Workflow

1. Fetch the external repo or file into a temporary directory.
2. Read the relevant `SKILL.md` or prompt files as text before running anything.
3. Check license, provenance, and whether the content is useful beyond one host.
4. Reject telemetry, update checks, shell hooks, memory preloads, default-agent
   fanout, host-specific paths, or giant always-on prompts.
5. Normalize the useful method into a concise ASCII `SKILL.md` with frontmatter.
6. Keep it lazy: no default routing, no startup preload, no lifecycle gate.
7. Add focused tests or docs only when the new skill changes install contracts.
8. Run `scripts/validate-bundle.ps1` and an install smoke when install behavior
   changed.

## Acceptance Bar

Accept a skill only when it adds a reusable behavior the lean loop does not
already cover. Prefer one narrow skill over a large omnibus prompt.

```text
SKILL_IMPORT: accepted|rejected|needs-review
- Source:
- Useful idea:
- Rejected baggage:
- Installed path:
- Validation:
```
