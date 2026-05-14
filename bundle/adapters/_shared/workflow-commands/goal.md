---
description: "User-typed /goal entry point. Takes a stated goal, classifies it (CODE / DESIGN / INVESTIGATION / REFACTOR / BOOTSTRAP / MULTI), and runs the matching kit workflow pipeline end-to-end via the correct sub-workflow commands: /build for CODE/REFACTOR, /investigate for INVESTIGATION, /analyze for ANALYSIS/RESEARCH, /review for REVIEW-only, /bootstrap-harness for BOOTSTRAP. Iterates with reviewer gates (cap: 6) until the goal is provably achieved. For simple single-edit tasks, triages to /build immediately."
---

# /goal

You are the __HOST_NAME__ session acting as goal orchestrator. The user invoked /goal because they want autonomous, end-to-end achievement of a multi-step goal. You ARE the top-level orchestrator; do NOT spawn another goal-orchestrator or build-orchestrator.

## Core contract

You classify the goal, pick the correct kit workflow as the primary pipeline, and iterate using that workflow — not ad-hoc agent calls. The kit workflows (/build, /plan, /review, /analyze, /investigate, /redesign, /bootstrap-harness) are your PRIMARY TOOLS, not just routing entries or leaf-agent fallbacks.

## Goal type → workflow routing

| Goal type | Primary pipeline | Fallback (if workflow unavailable on this host) |
|---|---|---|
| **CODE** — implement / fix / change code | Run `/build` with the goal as the request | Spawn `workflow-implementer` via Task following /build phases |
| **REFACTOR** — behavior-identical restructure | Run `/build` with explicit "behavior must be identical" constraint | Spawn `workflow-implementer` + `modularity-expert` |
| **INVESTIGATION** — debug / diagnose / root-cause | Run `/investigate` with the symptom | Spawn `workflow-explorer` x3 following /investigate phases |
| **ANALYSIS** — research / compare / evaluate | Run `/analyze` with the question | Spawn `workflow-explorer` + `workflow-skeptic` following /analyze phases |
| **REVIEW** — code review / audit (no implementation) | Run `/review` with diff context | Spawn `code-quality-reviewer` + `security-reviewer` |
| **DESIGN** — UI redesign / visual overhaul | Run `/redesign` or follow the DESIGN pipeline inline | Spawn `ux-driver` + `ui-driver` + aesthetic-director skill |
| **BOOTSTRAP** — missing `.kit/` or `.wiki/` | Run `/bootstrap-harness` | Read `__SKILL_ROOT__/bootstrap-harness/SKILL.md` and execute inline |
| **MULTI** — spans multiple types | Run primary pipeline, then secondary in order | State the sequence explicitly before starting |

## Phase -1 — Information sufficiency

Before doing anything, assess: can you define at least ONE concrete, observable success criterion from this goal?

**Critically underspecified if:**
- Goal is stated only as an abstract outcome with no measurable signal (e.g., "make it better")
- You cannot identify even one likely file, component, or behavior that must change
- 3+ fundamental decision forks exist where different answers lead to completely different approaches

**If critically underspecified:** output `INFO_NEEDED: <one compound question covering the most critical unknowns>` and stop. Cap: 1 round. If user does not clarify, document `ASSUMPTION: <text>` for each unknown and proceed.

**If sufficiently specified:** output `INFO_SUFFICIENT: proceeding` and continue to Phase 0.

## Phase 0 — Triage

Is this truly a goal-level task? STOP and redirect to the direct workflow if:
- Single-edit with obvious scope → tell user to use `/build` directly.
- Pure documentation update → no goal loop needed.

Otherwise output `TRIAGE: goal | reason: <why multi-step / iterative goal loop is warranted>` and continue.

## Phase 0.5 — Goal type classification

Output: `GOAL_TYPE: <CODE|DESIGN|INVESTIGATION|ANALYSIS|REFACTOR|REVIEW|BOOTSTRAP|MULTI>` plus a one-sentence reason.

For MULTI: list the ordered sub-types.


## Phase 1 — Goal capture

Restate the user's goal verbatim. Enumerate:
- **Success criteria**: each item CONCRETE and OBSERVABLE.
- **Scope IN**: work items required.
- **Scope OUT**: adjacent issues you will NOT fix.
- **Primary workflow**: which kit command will be used (e.g. `/build`).
- **Verification command**: exact command whose exit-0 signals completion.

If anything is ambiguous, proceed to Phase 2; otherwise continue to Phase 1.5.

## Phase 1.5 — Information sufficiency

Output: `INFO_STATUS: <SUFFICIENT | INSUFFICIENT> | reason: <text>`.

Mark `INSUFFICIENT` only when missing facts would change workflow choice, planning decision, or the verification command.

If `INSUFFICIENT`, go to Phase 2. Otherwise continue to Phase 2.5.

## Phase 2 — Clarification (cap: 3 rounds)

Ask only the questions that would change which pipeline you pick, whether Phase 2.5 should choose `NEEDS-PLAN`, or what the verification command is. After 3 rounds, document `ASSUMPTION: <text>`, then re-run Phase 1.5 once. If `INFO_STATUS` is still `INSUFFICIENT`, bail.

## Phase 2.5 — Planning decision (CODE/REFACTOR goals only)

Skip for INVESTIGATION, ANALYSIS, DESIGN, BOOTSTRAP, REVIEW goals.

Decide: should explicit planning run before executing?

**Skip planning — route directly to the workflow** if:
- Goal has a clear, concrete spec (specific files, exact expected behavior described)
- Change is isolated (≤3 files, no cross-cutting concern)
- A plan artifact from this session already exists

**Run planning phases first** if:
- Goal is an outcome statement, not a spec (e.g., "improve X", "make Y more robust")
- Change touches cross-cutting concerns (shared types, multiple modules, API contracts)
- Architectural decision required (new abstractions, interface changes, module splits)
- Likely >5 files affected

**If planning is warranted:** Run `/plan` (or equivalent planning phases). After the plan is produced, judge:
- `PLAN_SERVES_GOAL: YES` — all Phase 1 success criteria are addressable by this plan → proceed to `/build` and pass the plan path as context. Instruct `/build` that the plan already captures the exploration context (skip /build's own recon phase to avoid double exploration).
- `PLAN_SERVES_GOAL: NO` — state the gap explicitly → re-run planning with the gap as an additional constraint. Cap: 2 planning rounds.

**Efficiency invariant:** Do NOT invoke `/plan` again from within `/build`. One planning pass, then build. `/build`'s internal exploration is skippable when a plan exists.

## Phase 3 — Execute primary workflow

Run the workflow mapped from Phase 0.5. Pass the goal verbatim, success criteria, scope IN/OUT, verification command, and Phase 2.5 result into the workflow. If Phase 2.5 chose `NEEDS-PLAN`, include the plan output as context. Let the workflow's own phases handle exploration, implementation, review, and verification.

For MULTI goals: run the primary workflow to completion (verified), then start the secondary workflow.

### Iteration gate (cap: 6 for CODE/REFACTOR; 3 for INVESTIGATION/ANALYSIS)

After each workflow execution:
1. Check verification: did the workflow exit green?
2. Check scope: are all success criteria observable from the output?
3. If YES to both → CONVERGED, proceed to Phase 4.
4. If NO → re-run the workflow with the deltas from the previous iteration as additional context. Tag the re-run with `ITERATION N` so the workflow agent knows this is a follow-up.

**Stuck detection**: if the same BLOCKING issue appears in 3 consecutive iterations → bail.

## Phase 4 — Iron Law check

After the workflow reports convergence, confirm directly:
- Run the verification command yourself (Bash) and capture the exit code.
- If exit 0 → continue.
- If non-zero → do NOT claim done; re-enter the iteration loop with the failure output as context.

## Phase 4.5 — Self-evaluation (goal verdict)

Before producing the handoff, evaluate: did the outcome actually achieve the original stated goal?

Output `GOAL_VERDICT: <verdict>` where verdict is ONE of:

- **ON_TRACK** — All Phase 1 success criteria are observably met, verification green, scope respected, no significant drift from stated goal.
- **UNDER_DELIVERED** — Verification passes but ≥1 success criterion is not demonstrably met. List the unmet criteria explicitly.
- **OFF_TRACK** — Implementation solved a related but different problem; observable drift from the stated goal.
- **NEEDS_REBUILD** — Verification fails at iteration cap, or the approach taken was fundamentally wrong for the goal.
- **NEEDS_CLARIFICATION** — Discovered mid-execution that achieving the goal requires a user decision that was not available at start.

**Action per verdict:**
- **ON_TRACK** → proceed to Phase 5 handoff with `ACHIEVED` status.
- **UNDER_DELIVERED** → attempt one targeted iteration covering only the unmet criteria. If still partial after 1 retry, proceed to Phase 5 with `PARTIAL` status; list what was and was not delivered.
- **OFF_TRACK** → surface the drift explicitly, ask user whether to rollback and restart with the corrected interpretation or accept the partial result.
- **NEEDS_REBUILD** → bail immediately; output root cause (1-2 sentences) and a specific re-prompt suggestion the user can copy.
- **NEEDS_CLARIFICATION** → surface the specific question(s) to the user; do not produce a final handoff until answered.

## Phase 5 — Handoff

**FIRST line** (machine-parseable):
```
GOAL_STATUS: <ACHIEVED | PARTIAL | FAILED-AT-CAP | FAILED-AT-VERIFY | STUCK | TRIAGED-OUT | NEEDS-CLARIFICATION> | type: <type> | workflow: <workflow used> | iterations: <N> | verification: exit <code> | verdict: <ON_TRACK|UNDER_DELIVERED|OFF_TRACK|NEEDS_REBUILD|NEEDS_CLARIFICATION>
```

Then: goal verbatim, pipeline used, what changed (file list if CODE/REFACTOR), verification status, information sufficiency result, planning decision, self-evaluation rationale, iteration count, any assumptions made, scope-OUT items observed but not addressed.

## When to bail out

- Phase 1.5 remains `INSUFFICIENT` after the Phase 2 cap → bail.
- Phase 2.5 returns `NEEDS-PLAN` and `/plan` does not produce an actionable plan → bail.
- The same BLOCKING issue appears in 3 consecutive iterations → bail.
- Phase 4.5 returns `NEEDS_REBUILD`, `NEEDS_CLARIFICATION`, or a second `OFF_TRACK` occurrence → bail.


## What NOT to do

- Do NOT skip Phase 1.5, Phase 2.5, or Phase 4.5.
- Do NOT skip Phase 4 (Iron Law). "The workflow said it passed" is not evidence.
- Do NOT run leaf agents (workflow-implementer, workflow-explorer, etc.) directly when a kit workflow command covers the goal type. Routes first; leaf agents as fallback only.
- Do NOT recurse into another goal-orchestrator.
- Do NOT widen scope mid-loop. New scope → bail and ask the user.
- Do NOT continue with `INSUFFICIENT` information or an unresolved `NEEDS-PLAN` decision.
- Do NOT spawn adversarial-reviewer unless the user explicitly requests it or the change is a security-critical rewrite.
