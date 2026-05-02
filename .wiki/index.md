# Caspar Bannink Agentic Coding Kit -- Wiki Index

A disciplined harness for plan-first, multi-agent coding. PowerShell-based
tooling, cross-CLI adapter system. Production purpose: install once
(`pwsh ./scripts/install.ps1 -For all`), then every Claude Code / OpenCode /
Codex / Copilot / Kilo session in any repo on the device speaks the same
workflow language (commands, classifications, gates, lifecycle).

## Sections

The kit doesn't currently use per-section docs in `.wiki/sections/` -- the
codebase is its own structure (skills, tools, adapters), and the per-skill
`SKILL.md` files plus the per-tool comment headers are the canonical
reference. If `.wiki/sections/` is added later, list each here in
dependency order.

## Cross-cutting

- [`features.md`](features.md) -- full user-visible feature catalog (slash commands, sub-agents, skills, tools, adapters, lifecycle, frontend loop, self-improvement, memory routing)
- [`.features`](.features) -- machine-readable feature ID list (~130 IDs)
- [`../README.md`](../README.md) -- install, quick start, repo layout, honest pre-v1 caveats
- [`../NOTICE.md`](../NOTICE.md) -- third-party attribution (gstack, superpowers, autoresearch)
- [`../bundle/global/.agents/skills/`](../bundle/global/.agents/skills/) -- 27 skills with full SKILL.md docs each
- [`../bundle/global/.agents/tools/`](../bundle/global/.agents/tools/) -- 30+ tools with header docs
- [`../bundle/adapters/`](../bundle/adapters/) -- per-CLI adapter dirs

## How agents use this wiki

Skills do not bulk-load `.wiki/`. They use the lazy-load resolver:

```
pwsh ~/.agents/tools/wiki-resolver.ps1 -Task "<desc>" -ChangedFiles "<list>" -RepoRoot .
```

The resolver returns only sections whose `Key files` overlap with the
changed-file set. Update sections surgically when their files change --
do not let pages drift. Run `wiki-compress.ps1` periodically to flag
bloat (sections ≤150, architecture ≤200, features ≤300, index ≤100).

The kit's own `features.md` is updated by hand on every commit that adds
or modifies a slash command, sub-agent, skill, tool, adapter, validator,
install flag, or lifecycle hook.

## Last updated

2026-05-02 by `/wiki-init` retrofit (the kit eats its own dogfood).
