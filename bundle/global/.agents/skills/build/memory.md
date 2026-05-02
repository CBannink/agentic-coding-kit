# Build Skill — Accumulated Knowledge

Cross-repo patterns confirmed across multiple /build sessions.
**Scope**: global skill-level (not repo-specific).
- Repo facts → `.codex/context/memory.md`
- Session progress → `~/.agents/session-state/{id}/handoffs.md`
- Workflow improvement proposals → `~/.agents/context/reflections.md`

## Write Gate
Before adding an entry ask: "Would this pattern help a future /build session in a completely different repo?"
If no → write to the session private handoff instead.

## Format
```
- [DATE] [H/M/L confidence] [domain: implementation|testing|git|debugging|tooling]
  Pattern: {one-line}
  Evidence: {where confirmed — repo or session context}
  Apply when: {trigger condition}
```
Max 20 entries. Promote to build/SKILL.md if confirmed HIGH in 3+ repos.

---

## Confirmed Patterns

- [2026-04-27] [H confidence] [domain: testing]
  Pattern: Thin local UIs over scripts drift on defaults, artifact parsing, and unsafe rendering unless those are checked explicitly.
  Evidence: Agentic-Workflow-Eval UI review found default mismatch, missing score-shape handling, and raw HTML rendering risk.
  Apply when: a /build task adds a UI/control panel over existing scripts, run artifacts, or generated metadata.
