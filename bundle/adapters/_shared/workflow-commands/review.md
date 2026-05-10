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
## Phase 5b — Mechanical writeback gate (run this, do not skip)

After verification passes, run the writeback gate via Bash:

```
pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "$CLAUDE_SESSION_ID"
```

Output ends with `OK writeback: ...` (proceed) or `WARN NO WRITEBACK -- ...`. If WARN: either update `.wiki/features.md` / `.kit/context/memory.md` and re-run, OR include the warning in your final response so the user sees the gap. Do NOT silently skip.

## Phase 5c — Reflect trigger (mechanical)

Check `~/.agents/context/reflections.md` length. If 5+ unaddressed entries: spawn the `reflect` skill via the Skill tool (or surface to user "5+ workflow reflections accumulated, recommend running /reflect"). Mechanical, not vibes.

## Simplification policy (revised — fewer spawns by default)

For ISOLATED scope (Phase 0 classified):
- Phase 1 explorer: SKIP if codebase small / already understood.
- Phase 3 reviewers: code-quality-reviewer ONLY.
- Phase 4 adversarial: SKIP.
- Phase 5 final-verifier: orchestrator may run the verification command inline + check status itself; spawn final-verifier only if the change crosses module boundaries.
- Min spawns for ISOLATED: 1 (workflow-implementer if multi-file) or 0 (inline edits + inline verify).

For SHARED scope (default for most multi-file changes):
- Phase 1 explorer: spawn IF codebase unfamiliar.
- Phase 2 workflow-implementer: ALWAYS.
- Phase 3 reviewers: code-quality-reviewer ALWAYS. security-reviewer ONLY if auth/external-HTTP/DB-writes/file-paths/permissions touched. modularity-expert ONLY if new files added OR shared types changed OR DI/container wiring changed.
- Phase 4 adversarial: SKIP. (Was previously also SHARED -- now CRITICAL-only.)
- Phase 5 final-verifier: ALWAYS.
- Typical SHARED spawn count: 4 (explorer + implementer + code-quality + final-verifier). +1 if security trigger fires. +1 if modularity trigger fires. Max 6.

For CRITICAL scope (auth, schema migration, breaking change):
- Full pipeline: explorer + implementer + ALL three reviewers (quality + security + modularity) + adversarial + final-verifier = 7 spawns.
- Plus extra fix-loop iterations if reviewers find blocking issues.

Rule of thumb: prefer 1-line inline edits over implementer spawn. Prefer ONE reviewer over THREE unless there's a real reason. Adversarial pass is expensive; reserve it for CRITICAL changes that warrant the cost.