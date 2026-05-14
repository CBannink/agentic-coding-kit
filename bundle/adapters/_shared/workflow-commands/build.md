---
description: User-typed /build entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates; spawns workflow-explorer / workflow-implementer / specialist agents (code-quality-reviewer, security-reviewer, modularity-expert, final-verifier) via the Task tool per phase. Description-match also routes to the matching build-orchestrator subagent if loaded; both paths reach the same leaves.
---

# /build

You are the main Claude Code / OpenCode session. The user invoked /build because they want to implement / fix / refactor / change code. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Run the kit's phased build pipeline. You ARE the orchestrator. Delegate to leaf subagents via the Task tool when delegation pays off; do simple edits inline.

If a `build-orchestrator` subagent loaded via description-match auto-routing, it will run this same pipeline in its own fresh context — fine, let it. If you reached this command via the user typing `/build`, YOU run the pipeline.

## Phase 0 — Scope

Read `git status` + `git diff --stat HEAD`. Classify:
- **ISOLATED** — 1 module, no shared types, ≤5 files. Inline edits OK; spawn workflow-implementer only for genuinely complex logic.
- **SHARED** — 2+ modules or shared interfaces. Spawn workflow-implementer for the change.
- **CRITICAL** — auth, schema migration, breaking change. Spawn workflow-implementer + extra adversarial pressure.

## Phase 1 — Context (when needed)

If the change touches >2 unfamiliar files OR you need to discover code patterns: spawn `workflow-explorer` via Task with the user's verbatim request + 3-5 likely files to explore. Read its synthesis, then proceed.

If the codebase is small or already understood: skip this phase.

## Phase 2 — Implementation

For SHARED + CRITICAL or any multi-file change: spawn `workflow-implementer` via Task with:
- The user's request verbatim.
- The explorer synthesis (compact form) if Phase 1 ran.
- Explicit list of files in scope.
- The verification command (test/lint/build) the implementer must run after editing.

For ISOLATED single-file mechanical edits: do them inline with Read + Edit.

## Phase 3 — Review (single reviewer by default)

**One reviewer covers most cases.** Pick ONE based on dominant diff signal:

- New files / moved files / shared types / DI wiring → `modularity-expert`
- Auth / external HTTP / DB writes / file paths / user input → `security-reviewer`
- Everything else (default) → `code-quality-reviewer`

Spawn a SECOND reviewer ONLY if the first surfaces a finding clearly outside its lane (e.g. modularity-expert flags a missing input-validation that needs security-reviewer follow-up).

If the reviewer returns BLOCKING findings: spawn `workflow-implementer` again with the findings as deltas. Cap at 3 iterations of fix-loop.

## Phase 4 — Adversarial pass (REMOVED from default)

`adversarial-reviewer` is no longer in the default matrix. Evidence from session reflections + Anthropic multi-agent research: critic loops past 2-3 reviewers degrade output (false-positive flooding, the critic finds problems to justify itself). `code-quality-reviewer` + `final-verifier` already catch the genuine issues.

Spawn `adversarial-reviewer` ONLY if the user explicitly asks for it OR the change is a security-critical rewrite (auth subsystem, crypto, schema migration with data loss risk).

## Phase 5 — Iron Law gate

Run the verification command yourself (Bash) and capture exit code. Then spawn `final-verifier` via Task to confirm:
- Verification command ran fresh.
- Exit code 0 was captured.
- No code modified after the last verification.

If final-verifier returns red: surface to user, do NOT claim "done."

## Phase 6 — Handoff

One-paragraph summary: files changed (1 line each), behavior delivered, verification status. If `.wiki/features.md` exists and the change added a user-visible feature, append a 1-line entry.

## What NOT to do

- Do NOT spawn another orchestrator (no `build-orchestrator`, no `goal-orchestrator`) — you ARE the orchestrator, that's recursion.
- Do NOT skip Phase 5 (Iron Law). "Tests probably pass" is forbidden.
- Do NOT add scope. If the user asked for X and you notice Y, mention Y in handoff but don't fix it.
## Phase 5b — Mechanical writeback gate (run this, do not skip)

After verification passes, run the writeback gate via Bash:

```
pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "$CLAUDE_SESSION_ID"
```

Output ends with `OK writeback: ...` (proceed) or `WARN NO WRITEBACK -- ...`. If WARN: either update `.wiki/features.md` / `.kit/context/memory.md` and re-run, OR include the warning in your final response so the user sees the gap. Do NOT silently skip.

## Phase 5c — Reflect trigger (mechanical)

Check `~/.agents/context/reflections.md` length. If 5+ unaddressed entries: spawn the `reflect` skill via the Skill tool (or surface to user "5+ workflow reflections accumulated, recommend running /reflect"). Mechanical, not vibes.

## Simplification policy (v2 — minimal default, escalate only on evidence)

**Per-tier spawn budgets:**

| Tier | Typical | Max | Composition |
|---|---|---|---|
| ISOLATED | **0** | 1 | Inline edits + inline verify. Spawn workflow-implementer only if genuinely complex multi-file logic. |
| SHARED (default) | **3** | 4 | workflow-implementer + 1 reviewer (picked by dominant diff signal) + final-verifier. +1 explorer if codebase unfamiliar. |
| CRITICAL | **5** | 7 | explorer + implementer + 1-2 reviewers + final-verifier + (optional) adversarial-reviewer if user requests OR auth/schema/crypto rewrite. |

**Single-reviewer rule (Phase 3):** spawn ONE reviewer based on dominant diff signal. Spawn a second only if the first surfaces a finding clearly outside its lane.

**Adversarial-reviewer NOT in default matrix at any tier.** Evidence: critic loops past 2-3 reviewers produce diminishing returns + false-positive flooding (Anthropic multi-agent research; barkain delegation-orchestrator deprecation note). Reserve for explicit user-requested adversarial passes or genuine security-critical rewrites.

**Rule of thumb:** prefer 1-line inline edits over implementer spawn. Prefer ONE reviewer over multiple unless evidence demands more. Every spawn beyond the typical count must be justifiable in the handoff.