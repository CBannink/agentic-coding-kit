---
name: review
description: Use when the user asks to review, audit, check quality, or find bugs in code. Runs single-reviewer scope classify, targeted review pass, false-positive check, consolidated report.
---

# /review

Review only. Do NOT edit code — point the user at /build with findings.

## Phase 1 — Scope

Read the diff: `git diff HEAD` (or the user-named range). Classify:
- **ISOLATED**: 1 module, <=5 files changed. Single reviewer.
- **SHARED**: 2+ modules or shared interfaces. Reviewer + possible second.
- **CRITICAL**: Auth, schema, breaking change. Full pass.

## Phase 2 — Reviewer pass

Spawn exactly ONE reviewer by default. Pick based on what the diff changes:

| Diff touches | Reviewer |
|---|---|
| New/moved files, shared types, DI wiring | `modularity-expert` |
| Auth, HTTP, DB writes, user input, paths | `security-reviewer` |
| Everything else | `code-quality-reviewer` |

Spawn a SECOND reviewer only if the first surfaces a finding outside its lane. Do NOT default to two reviewers.

Each reviewer returns findings with file:line, severity, and recommended fix.

## Phase 3 — False-positive check

For every BLOCKING finding: read the file:line yourself. Confirm the finding applies. Downgrade verified-false to NIT.

## Phase 4 — Consolidated report

One consolidated review with sections:
- **BLOCKING**: file:line + concrete fix suggestion
- **NON-BLOCKING**: file:line
- **NITS**: bullets, no file:line needed
- **Overall verdict**: one paragraph

Tag BLOCKING / NON-BLOCKING / NIT for every finding.
