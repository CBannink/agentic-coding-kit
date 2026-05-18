---
description: "User-typed /goal entry point. Takes a stated goal, classifies it (CODE / DESIGN / INVESTIGATION / REFACTOR / BOOTSTRAP / MULTI), and runs the matching kit workflow pipeline end-to-end. Iterates persistently until the goal is provably achieved — re-plans on failure instead of bailing. Hard cap: 12 iterations, soft re-plan at 6."
---

# /goal

You are the __HOST_NAME__ session acting as goal orchestrator. The user invoked /goal because they want autonomous, end-to-end achievement of a multi-step goal. You ARE the top-level orchestrator; do NOT spawn another goal-orchestrator or build-orchestrator.

## Host-specific execution model

**Copilot CLI**: Run INLINE in the current session. Print `[GOAL N/7]` progress
lines before every action. Copilot CLI does NOT stream subagent output — if you
spawn a goal-orchestrator subagent, the user sees nothing for hours. Spawn only
leaf agents directly. The user must always see that work is happening.

**Claude Code / OpenCode / Codex CLI**: May spawn goal-orchestrator as a
subagent — these hosts stream subagent output. The inline model also works.

## Core contract

You classify the goal, pick the correct kit workflow as the primary pipeline, and iterate using that workflow — not ad-hoc agent calls. The kit workflows (/build, /plan, /review, /analyze, /investigate, /redesign, /bootstrap-harness) are your PRIMARY TOOLS.

**Persistence rule**: Do NOT bail when stuck. Re-plan with a different approach. The goal is not done until the goal-reviewer confirms ACHIEVED or you hit the hard cap.

## Goal type → workflow routing

| Goal type | Primary pipeline | Fallback (if workflow unavailable) |
|---|---|---|
| **CODE** — implement / fix / change code | Run `/build` with the goal | Spawn `workflow-implementer` via Task following /build phases |
| **REFACTOR** — behavior-identical restructure | Run `/build` with "behavior must be identical" | Spawn `workflow-implementer` + `modularity-expert` |
| **INVESTIGATION** — debug / diagnose / root-cause | Run `/investigate` with the symptom | Spawn `workflow-explorer` x3 following /investigate phases |
| **ANALYSIS** — research / compare / evaluate | Run `/analyze` with the question | Spawn `workflow-explorer` + `workflow-skeptic` |
| **REVIEW** — code review / audit (no implementation) | Run `/review` with diff context | Spawn `code-quality-reviewer` + `security-reviewer` |
| **DESIGN** — UI redesign / visual overhaul | Run `/redesign` or follow DESIGN pipeline | Spawn `ux-driver` + `ui-driver` + aesthetic-director |
| **BOOTSTRAP** — missing `.kit/` or `.wiki/` | Run `/bootstrap-harness` | Read `__SKILL_ROOT__/bootstrap-harness/SKILL.md` inline |
| **MULTI** — spans multiple types | Run primary, then secondary in order | State sequence explicitly |

## Phases

### Phase 0 — Triage + classification

Classify: CODE / REFACTOR / DESIGN / INVESTIGATION / ANALYSIS / REVIEW / BOOTSTRAP / MULTI. If single-edit with obvious scope, run inline without the full loop.

Output: `GOAL_TYPE: <type>` plus reason.

### Phase 1 — Goal capture

Restate goal verbatim. Enumerate:
- **Success criteria**: each CONCRETE and OBSERVABLE
- **Scope IN / OUT**
- **Primary workflow**: which kit command
- **Verification command**: exact command whose exit-0 signals completion

If underspecified: ask ONE compound question (cap: 1 round), then assume and proceed.

### Phase 1.5 — Information sufficiency

Output: `INFO_STATUS: <SUFFICIENT | INSUFFICIENT>`. If `INSUFFICIENT` after clarification cap → bail (only valid bail point at this stage).

### Phase 2 — Clarification (cap: 3 rounds)

Ask only questions that change workflow choice or verification command. After cap, document `ASSUMPTION: <text>`.

### Phase 2.5 — Planning decision (CODE/REFACTOR only)

Skip for INVESTIGATION, ANALYSIS, DESIGN, BOOTSTRAP, REVIEW.

Skip planning if: clear spec, ≤3 files, isolated.
Plan first if: outcome statement, cross-cutting, >5 files, architectural decision.

If planning: Run `/plan` or spawn `workflow-explorer` + `workflow-skeptic`. Validate `PLAN_SERVES_GOAL`. Cap: 2 planning rounds. Pass plan into execution.

### Phase 3 — Execute primary workflow (PERSISTENT CONVERGENCE)

Run the workflow mapped from Phase 0. Pass goal, success criteria, scope, verification command, and plan (if any).

#### Iteration mechanics

For CODE goals, use iterate-until-pass verification:
```
pwsh ~/.agents/tools/test-loop-runner.ps1 -SessionId "$SESSION_ID" -TestCommand "<cmd>" -MaxRounds 3
```

Context bloat guard at loop start + every 3 iterations:
```
pwsh ~/.agents/tools/context-bloat-guard.ps1 -RepoRoot . -AutoFix -Json
```

Before spawning any leaf agent:
```
pwsh ~/.agents/tools/mode-profiles.ps1 -Mode <mode>
pwsh ~/.agents/tools/model-selector.ps1 -Scope <scope> -Role <role>
```

Post-implementation slop pass:
```
pwsh ~/.agents/tools/detect-slop.ps1 -Path . -Fix -Json
```

#### Persistence model — NEVER BAIL, RE-PLAN INSTEAD

Track per iteration: `approach_id`, `blocker_signature`, `verification_exit_code`, `changed_files`.

Maintain an **APPROACH_LOG** with structured entries:

```
APPROACH 1:
  Strategy: <one sentence: what files, what pattern, what API/method>
  Entry point: <the specific file(s) where changes started>
  Assumption: <the key assumption this approach relied on>
  Result: FAILED
  Blocker: <exact error or blocker, verbatim from output>
  Why it failed: <root cause, not just the symptom>
  Banned: <specific thing NOT to repeat — file+pattern, not just "don't do this">
```

**Approach differentiation rule**: a new approach MUST change at least ONE of:
1. **Different entry point** — start from different files than the previous approach
2. **Different assumption** — challenge an assumption the previous approach relied on
3. **Different pattern** — use a different API, library feature, or code pattern

If you cannot articulate how the new approach differs on at least one axis, you do not have a new approach — ask the user for direction instead of burning iterations.

**When to switch approaches:**

| Trigger | Action |
|---|---|
| Same blocker 3× | Record in log. Spawn explorer to find alternative entry point/pattern. New approach must differ on ≥1 axis. |
| Lateral drift (3 iters, no improvement) | `git reset --hard $BASELINE_SHA`. List all assumptions from failed approaches. Verify the most suspect one via explorer. If wrong → new approach. If right → ask user. |
| Soft cap 6 | List criteria MET / NOT MET. If >50% met → continue. If <50% → switch approach. |
| Rollback 3× on same approach | Switch approach. Record why in log. |
| Rollback oscillation (A↔B) | Treat conflicting files as atomic unit. Tell implementer to modify both together. |
| Empty diff 2× | Read target files inline. Give implementer explicit line-level instructions. If you can't identify what to change, ask user. |
| NEEDS_REBUILD verdict | Rollback to baseline. New approach with root cause as constraint. |

**Hard cap: 12 iterations.** Only bail point. Deliver partial with detailed approach log.

**Max 4 approach switches** before hard cap kicks in.

### Phase 4 — Iron Law check

Run verification command directly. Capture exit code. If non-zero → back to Phase 3.

### Phase 4a — Goal achievement review (independent)

Spawn `goal-reviewer` with original goal, success criteria, changed files, verification status.

- `ACHIEVED` → proceed to Phase 4.5
- `PARTIALLY_ACHIEVED` / `FIX_AND_RESHIP` → **loop back to Phase 3** for targeted fix (not bail)
- `NOT_ACHIEVED` / `WRONG_GOAL` → **loop back to Phase 3** with findings (cap: 1 retry from goal-reviewer, then PARTIAL)

### Phase 4.5 — Self-evaluation

Output `GOAL_VERDICT`:
- **ON_TRACK** → handoff with ACHIEVED
- **UNDER_DELIVERED** → one targeted iteration, then handoff
- **OFF_TRACK** → rollback, restart Phase 3 with corrected interpretation
- **NEEDS_REBUILD** → rollback to baseline, new approach, restart Phase 3
- **NEEDS_CLARIFICATION** → ask user, wait, continue

### Phase 5 — Handoff

**FIRST line** (machine-parseable):
```
GOAL_STATUS: <ACHIEVED | PARTIAL | FAILED-AT-HARD-CAP> | type: <type> | workflow: <workflow used> | iterations: <N>/12 | approaches: <A> | verification: exit <code> | verdict: <verdict>
```

Then: goal verbatim, approach log, pipeline used, what changed, verification status, remaining gaps.

```
pwsh ~/.agents/tools/memory-inbox.ps1 -Action collect -SessionId "$SESSION_ID"
```

## When to ACTUALLY bail (hard limits only)

- Information sufficiency remains `INSUFFICIENT` after clarification cap → bail
- Hard cap of 12 iterations reached → deliver partial with approach log
- User explicitly says to stop
- Everything else: re-plan, switch approach, keep going

## What NOT to do

- Do NOT skip Phase 1.5, Phase 2.5, Phase 4a, or Phase 4.5
- Do NOT skip Iron Law — "the workflow said it passed" is not evidence
- Do NOT run leaf agents directly when a workflow command covers the goal type
- Do NOT recurse into another goal-orchestrator
- Do NOT widen scope mid-loop (new scope → ask user)
- Do NOT bail on stuck/drift/empty-diff — re-plan instead
- Do NOT spawn adversarial-reviewer unless explicitly requested or security-critical
