# Investigate Skill — Accumulated Knowledge

Cross-repo root-cause patterns confirmed across multiple /investigate sessions.
**Scope**: global skill-level (not repo-specific).

## Write Gate
Before adding an entry ask: "Would this root-cause pattern or elimination heuristic help future investigations in a different repo?"
If no → write to the session private handoff instead.

## Format
```
- [DATE] [H/M/L confidence] [domain: env|config|dependency|type-drift|flaky|ci|api]
  Pattern: {one-line — what symptom maps to what root cause}
  Evidence: {where confirmed}
  Eliminate early: {what to rule out first when this symptom appears}
```
Max 20 entries. Promote to investigate/SKILL.md if confirmed HIGH in 3+ investigations.

---

## Confirmed Patterns

*(empty — seed file; populate from confirmed multi-repo root-cause patterns)*
