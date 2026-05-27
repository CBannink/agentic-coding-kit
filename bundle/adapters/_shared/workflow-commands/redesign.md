---
description: User-typed /redesign entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates, decides mode, and spawns only leaf agents via the Task tool.
---

# /redesign

You are the main Claude Code / OpenCode session. The user invoked /redesign because they want to greenfield UI / multi-component visual redesign. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Greenfield UI work and multi-component visual redesign. Swarm-eligible. You ARE the orchestrator.

## Phase 1 — Aesthetic direction lock

If `DESIGN.md` exists, read it. Otherwise spawn `aesthetic-director` to lock typography, palette, density, motion. Without a locked direction, every component drifts toward generic defaults (Inter + purple gradient + rounded cards).

## Phase 2 — Current-state capture

Run `dev-server-runner.ps1` to start the dev server. Spawn `playwright-explorer` (or `playwright-navigator` first if routes are unmapped) to capture before-screenshots of every screen in scope.

## Phase 3 — Per-component design (parallel)

For each component in scope (max ~8 in parallel), spawn one Task call to:
- `design-driver` — for INLINE/TARGETED polish (single screen, single concern).
- `ux-driver` then `ui-driver` — for FULL redesign. UX runs first; if `structure_ok=false`, structure is broken and visual polish is blocked until structure is fixed.

## Phase 4 — Synthesis & implementation

Aggregate per-component proposals. Spawn `workflow-implementer` with the consolidated proposal as the implementation contract.

## Phase 5 — Visual diff verification

Capture after-screenshots. Spawn `ui-driver` again with before+after to confirm changes were intentional and no regression elsewhere. Run `visual-diff.ps1`.

## Phase 6 — Iron Law

Spawn `final-verifier`. For UI work, "tests pass" alone is insufficient — visual regression has to be checked.
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
