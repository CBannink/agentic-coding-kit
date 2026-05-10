---
description: User-typed /redesign entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates; spawns workflow-explorer / workflow-implementer / specialist agents (code-quality-reviewer, security-reviewer, modularity-expert, final-verifier) via the Task tool per phase. Description-match also routes to the matching redesign-orchestrator subagent if loaded; both paths reach the same leaves.
---

# /redesign

You are the main Claude Code / OpenCode session. The user invoked /redesign because they want to greenfield UI / multi-component visual redesign. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Greenfield UI work and multi-component visual redesign. Swarm-eligible. You ARE the orchestrator.

## Phase 1 — Aesthetic direction lock

If `DESIGN.md` exists, read it. Otherwise spawn `aesthetic-director` to lock typography, palette, density, motion. Without a locked direction, every component drifts toward the model's default (Inter + purple gradient + rounded cards).

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