---
name: goal
description: "User-typed /goal entry point. Classifies the stated goal (CODE / DESIGN / INVESTIGATION / REFACTOR / BOOTSTRAP / MULTI / PR_REVIEW) and runs the goal pipeline INLINE with progress output. MUST BE USED when the user types `/goal` or says 'achieve this autonomously', 'drive this to completion', or 'iterate until done'."
---

# /goal

YOU run this pipeline inline. Do NOT spawn `goal-orchestrator` as a subagent —
subagent output is invisible to the user (no streaming on Copilot CLI, delayed
on Claude Code). Running inline means the user sees progress between every spawn.

## Lifecycle

```
START: pwsh ~/.agents/tools/pre-session.ps1 -Mode goal -Task "<goal>"
       Read BRIEF. Note SessionId, scope, tier, prior handoffs.
GATES: state-gate.ps1 -Mark "context_loaded" / "implementation_done" / "verification_evidence" / "handoff_written"
END:   pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

## Phase 0 — Triage

Single-edit with obvious scope → redirect to `/build`. Pure docs update → no goal loop.
Otherwise: `TRIAGE: goal inline | reason: <why>`

## Phase 0.5 — Goal type classification

| Type | Route to | Pipeline |
|---|---|---|
| CODE / REFACTOR | `/build` | explore → implement → review → verify |
| DESIGN | `/redesign` | aesthetic-lock → capture → design → implement → visual-diff |
| INVESTIGATION | `/investigate` | parallel hypothesis explore → evidence → Build Brief |
| ANALYSIS | `/analyze` | multi-perspective explore → synthesize → verify |
| REVIEW | `/review` | reviewer fan-out → synthesis |
| BOOTSTRAP | `/bootstrap-harness` | scaffold `.kit/` + `.wiki/` |
| PR_REVIEW | `pr-reviewer` agent | structured review with verdict |
| MULTI | decompose | route each sub-goal in sequence |

**If a workflow command covers the goal type, USE IT.** Leaf agents are the fallback.
Output: `GOAL_TYPE: <type> | reason: <reason>`

## Phase 1 — Goal capture

Restate goal verbatim. Checklist: success criteria (concrete + observable),
scope IN, scope OUT, verification command (exact exit-0 signal).

## Phase 2 — Clarification (cap 3 rounds)

Smallest set of questions. After 3 rounds: `ASSUMPTION: <text>` and proceed.

## Phase 3 — Recon

```
[GOAL 3/8] Spawning workflow-explorer for recon...
```
Spawn `workflow-explorer` with goal, criteria, scope, 3-8 files, `.kit/context/memory.md`, `.wiki/index.md`.
Mark gate: `context_loaded`.

## Phase 4 — Design prep (DESIGN only)

Read or create `DESIGN.md` via aesthetic-director. Run `dev-server-runner.ps1`.
Capture before-screenshots via `playwright-runner.ps1 -Mode before`.

## Phase 5 — Build-review-iterate (cap 6 iterations)

Capture: `BASELINE_SHA = git rev-parse HEAD`

Each iteration — **output progress before every spawn:**
```
[GOAL 5/8] Iteration <N>/6 — Spawning workflow-implementer...
```
Prompt: ITERATION, GOAL, SUCCESS_CRITERIA, SCOPE_OUT, EXPLORER_SYNTHESIS,
VERIFICATION_COMMAND, DELTAS_FROM_LAST_ITERATION.

Run verification inline. Then:
```
[GOAL 5/8] Iteration <N>/6 — verification <pass|fail>. Spawning reviewer...
```

Reviewer selection by type:
- CODE: `code-quality-reviewer` + `security-reviewer` (if auth/IO) + `modularity-expert` (if shared types)
- DESIGN: `ux-driver` → `ui-driver` (if structure_ok) → `visual-diff.ps1`
- REFACTOR: `code-quality-reviewer` ("behavior identical") + `modularity-expert`
- INVESTIGATION: skip implementer — 1-3 `workflow-explorer` per hypothesis, write Build Brief

No BLOCKING → CONVERGED. BLOCKING → re-prompt implementer.
Same blocker 3× → STUCK. Empty diff 2× → STUCK. Rollback 3× → bail.
Mark gate: `implementation_done` on convergence.

## Phase 6 — DESIGN finalization (DESIGN only)

After-capture + visual-diff. Surface unintended regressions.

## Phase 7 — Iron Law

```
[GOAL 7/8] Spawning final-verifier...
```
Mark gate: `verification_evidence`.
Run writeback: `pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "<id>"`

## Phase 8 — Handoff

```
GOAL_STATUS: <ACHIEVED|PARTIAL|FAILED-AT-CAP|STUCK|TRIAGED-OUT> | type: <type> | iterations: <N>/6 | verification: exit <code> | files: <count>
```
Mark gate: `handoff_written`.

## Rules

- YOU are the orchestrator. Only spawn LEAF agents (explorer, implementer, reviewers, final-verifier).
- Emit `[GOAL N/8]` progress lines before every spawn so the user sees forward motion.
- Do NOT spawn `goal-orchestrator` as a subagent from here.
- Do NOT widen scope mid-loop. New scope = bail and ask.
- Do NOT skip Iron Law. "Tests probably pass" is forbidden.
