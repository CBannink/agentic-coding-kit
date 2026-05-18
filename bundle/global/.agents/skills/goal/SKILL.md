---
name: goal
description: Use when the user says "achieve this autonomously", "iterate until done", "drive this to completion", or any multi-step end-to-end task. Classifies type, routes to the correct workflow, iterates with review gates until provably achieved.
---

# /goal

Multi-step autonomous completion. Classify the goal, pick the right pipeline, iterate until done. Do NOT bail on failure — re-plan with a different approach.

## Phase 0 — Triage

- **Single-edit task with obvious scope**: redirect to `/build` instead.
- **Pure documentation**: no goal loop needed, write directly.
- **Multi-step, ambiguous, or cross-type**: continue with this workflow.

Output: `TRIAGE: goal | reason: <why>` or `TRIAGE: redirect to /build | reason: <why>`

## Phase 0.5 — Goal type classification

Pick ONE primary type:

| Type | Pipeline |
|---|---|
| **CODE** | /build → implement → review → verify |
| **REFACTOR** | /refactor → consequence-trace → implement → modularity-check → verify |
| **DESIGN** | /redesign → aesthetic-lock → capture → design → implement → visual-diff |
| **INVESTIGATION** | /investigate → hypotheses → evidence → Build Brief |
| **ANALYSIS** | /analyze → explore → synthesize → verify |
| **REVIEW** | /review → reviewer pass → verify |
| **BOOTSTRAP** | /bootstrap-harness → scaffold → init |
| **MULTI** | Decompose into sub-goals, route each independently, sequence the results |

Output: `GOAL_TYPE: <type> | reason: <reason>`

## Phase 1 — Goal capture

Restate the goal verbatim. Enumerate:
- **Success criteria**: each CONCRETE and OBSERVABLE
- **Scope IN**: work items required
- **Scope OUT**: adjacent issues you will NOT fix
- **Verification command**: exact command whose exit-0 signals completion

## Phase 2 — Brief planning decision (CODE/REFACTOR only)

Skip planning if: clear spec, <=3 files, isolated change. Plan first if: outcome statement, cross-cutting, >5 files, architectural decision.

If planning: spawn `workflow-explorer` + `workflow-skeptic` to produce a plan artifact, validate it against success criteria, then continue to Phase 3 with the plan as context.

## Phase 3 — Recon (exactly once)

Spawn `workflow-explorer` with: goal, success criteria, scope IN/OUT, 3-8 likely files, pointers to `.kit/context/memory.md` and `.wiki/index.md`. Skip if Phase 2 already produced a validated plan that covers the exploration surface.

## Phase 4 — Build-review-iterate loop (persistent convergence)

Capture baseline: `BASELINE_SHA = git rev-parse HEAD`

Each iteration:
1. Spawn `prompt-synthesizer` with: user goal, success criteria, APPROACH_LOG, exploration synthesis, deltas from last iteration, target type "implementer". Use its `PROMPT_SYNTHESIS` output as the implementer prompt.
2. Spawn `workflow-implementer` with the synthesized prompt.
3. Run slop detection: `pwsh ~/.agents/tools/detect-slop.ps1 -Path . -Fix -Json`. Spawn `slop-refactorer` if warning-severity findings remain.
4. Run verification inline. If non-zero, include error in next iteration's deltas for the prompt-synthesizer.
5. If verification green AND scope appears complete: spawn `prompt-synthesizer` with diff context + target reviewer type, then spawn the reviewer with the synthesized prompt.
6. No BLOCKING → converged. BLOCKING → re-prompt implementer with deltas.

**Stuck detection**: same file:line:rule blocker in 3 consecutive iterations → spawn `workflow-explorer` to find an alternative approach. Same 2-3 files oscillating as failure sources → tell implementer to modify them as a single atomic unit. 6 soft cap, 12 hard cap.

## Phase 5 — Goal achievement review

Spawn `goal-reviewer` with: original goal, success criteria, files changed, verification status. If NOT ACHIEVED, loop back to Phase 4 once with findings as constraints. If still not achieved, proceed with PARTIAL.

## Phase 6 — Final verification

Spawn `final-verifier` with BASELINE_SHA→HEAD diff, verification + last exit-0, goal verbatim + criteria. Self-evaluate verdict: ON_TRACK / UNDER_DELIVERED / OFF_TRACK / NEEDS_REBUILD.

## Phase 7 — Handoff

Output machine-parseable first line:
```
GOAL_STATUS: <ACHIEVED|PARTIAL|FAILED-AT-CAP> | type: <type> | iterations: <N>/12
```

Then: goal verbatim, approach log, files changed, verification status, remaining gaps.
