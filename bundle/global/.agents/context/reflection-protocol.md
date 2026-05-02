# Shared Reflection Protocol

Canonical reflection capture for all workflow modes and the harness.

## Trigger

- Embedded consolidation triggers at **5+ annotation-free entries**
- No soft-warning branch
- Promoted entries are **deleted**, never annotated

## Normalized entry format

Use one line per reflection entry:

```md
- [YYYY-MM-DD] [source:harness-auto|session] [scope:global|repo] [class:gating|routing|retrieval|verification|noise]
  Pattern: {one-line problem}
  Evidence: {specific evidence from session, gates, files, or counts}
  Suggested target: {narrowest target file}
```

## Harness-owned automatic capture

`post-session.ps1` should append normalized entries for objective workflow failures:
- missing required gates when session still registers
- verification override / Iron Law near-miss
- agent cap exceeded

Only objective failures belong here. Subjective prompt ideas still require session/reflection judgment.

## Promotion rules

- Repo-specific patterns → `.kit/workflows/*.md`
- Global workflow/skill patterns → `~/.agents/skills/*/SKILL.md`
- Global routing/mechanism patterns → `~/.agents/instructions.md`

If uncertain, target the narrowest file and leave the entry unpromoted.
