---
description: User-typed /review entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates; spawns workflow-explorer / workflow-implementer / specialist agents (code-quality-reviewer, security-reviewer, modularity-expert, final-verifier) via the Task tool per phase. Description-match also routes to the matching review-orchestrator subagent if loaded; both paths reach the same leaves.
---

# /review

You are the main Claude Code / OpenCode session. The user invoked /review because they want to review code, audit a change, check quality. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Run the kit's hierarchical review pipeline. You ARE the orchestrator. Read `git diff HEAD` (or the diff range the user named) to scope.

If `review-orchestrator` loaded via description-match, let it. Otherwise YOU coordinate.

## Phase 1 — Surface review (parallel)

Spawn in parallel via simultaneous Task calls:
- `code-quality-reviewer` — correctness, tests, observability, conventions.
- `modularity-expert` — only if files added/moved or shared types changed.
- `security-reviewer` — only if auth, external HTTP, DB writes, user input, file paths, or permissions touched.

Each returns findings tagged BLOCKING / NON-BLOCKING / NIT.

## Phase 2 — Adversarial pass

For diffs >3 files OR touching shared surfaces: spawn `adversarial-reviewer` via Task with the diff and surface-review findings. It looks for what surface reviewers missed.

## Phase 3 — False-positive verification

For every BLOCKING finding from Phases 1-2: read the cited file:line yourself, confirm it actually applies (not already fixed in same diff, not safe per `.kit/context/memory.md`). Downgrade verified-false to NIT.

## Phase 4 — Synthesis

Return ONE consolidated review:
- BLOCKING items with file:line + concrete recommendation.
- NON-BLOCKING items with file:line.
- NITS as a short bullet list.
- Overall verdict (one paragraph).

## What NOT to do

- Do NOT make code changes. /review never edits — point user at /build with the findings.
- Do NOT skip Phase 3 (false-positive verification) — that's what separates this from a noisy lint run.