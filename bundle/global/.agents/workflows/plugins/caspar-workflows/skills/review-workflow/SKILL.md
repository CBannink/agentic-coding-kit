---
name: review-workflow
description: Use when the user says /review or asks for a code review, audit, or quality check of existing code or a diff. Supports repo-local augmentation from AGENTS.md, CLAUDE.md, GEMINI.md, and .kit/workflows/review.md.
---

# Review Workflow

## Load Context First

Before reviewing, read these files when they exist:
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `.kit/workflows/shared.md`
- `.kit/workflows/review.md`
- `.kit/context/memory.md`
- `.kit/context/handoffs.md`
- `.kit/context/reflections.md`

## Default Agent Matrix

### Core Reviewers

- `software-reviewer`
  Purpose: logic, regressions, edge cases, architecture fit, and missing tests.
- `security-reviewer`
  Purpose: auth, trust boundaries, injection, leakage, abuse cases, and sensitive flows.
- `api-reviewer`
  Purpose: contract changes, integration compatibility, request/response semantics, and retries.
- `testing-reviewer`
  Purpose: test quality, missing coverage, and regression safety.

### Specialist Reviewers

- `performance-reviewer`
  Purpose: N+1s, heavy loops, latency multipliers, and resource hotspots.
- `maintainability-reviewer`
  Purpose: readability, coupling, complexity, and future breakage risk.
- `data-migration-reviewer`
  Purpose: rollout, backfill, reversibility, and data corruption risk when schema/data changes exist.
- `adversarial-reviewer`
  Purpose: find production failure modes and nasty edge cases the structured review misses.

### Verification

- `false-positive-verifier`
  Purpose: read actual code in context and downgrade noise before reporting.

## Prompt Catalog

Default role prompts live under:
- `plugins/caspar-workflows/prompts/review/`

## Workflow

1. Define review scope: diff, files, module, or branch.
2. Launch parallel reviewers for correctness, security, and integration concerns.
3. Add specialist reviewers when the diff shape warrants it:
   - `testing-reviewer` for behavior changes
   - `performance-reviewer` for hot paths or query-heavy code
   - `data-migration-reviewer` for schema/data changes
   - `maintainability-reviewer` when complexity balloons
4. Run `adversarial-reviewer` as a separate pass for production-risk thinking.
5. Run a verifier pass that reads actual code in context and filters noise.
6. Report findings ordered by severity with file:line references.
7. If the user asks for fixes, apply them and re-run relevant checks.
8. Write back review memory:
   - append active findings, attempted verifications, and next actions to `.kit/context/handoffs.md`
   - promote confirmed recurring patterns, repo-specific traps, and durable reviewer guidance to `.kit/context/memory.md`
   - append workflow or prompt improvement candidates to `.kit/context/reflections.md` when repeated review failures or false-positive patterns are detected

## Rules

- Prioritize bugs, regressions, security issues, and missing tests.
- Do not suggest unrelated feature work.
- Do not spend review budget on style-only comments in untouched code.
- Be explicit about residual risk and testing gaps if no findings are confirmed.
- Prefer gstack review posture for specialist decomposition and adversarial challenge.
- Prefer Superpowers reviewer discipline for concise actionable feedback and follow-through.
- Check `memory.md` before escalating recurring issues; distinguish new findings from known/deferred risks.
- Use `handoffs.md` to continue unfinished reviews across sessions.
- Never rewrite workflow prompts in-place during a normal review run.
- Store self-improvement candidates in `reflections.md` for later consolidation instead of mutating global skills ad hoc.

## Repo-Local Augmentation Contract

Repo-local review instructions may define:
- Mandatory review categories
- Severity policy
- Required commands for verification
- Domain-specific audit checks
- Specialist reviewers to always include or always suppress
- Rules for what belongs in `memory.md`, `handoffs.md`, or `reflections.md`
