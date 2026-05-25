---
name: build
description: Use when the user asks to implement, fix, refactor, change, add, or modify code. Runs a phased pipeline: scope classify, explore, implement, review, verify, handoff.
---

# /build

Execute these phases in order. Each phase tells you which agents to spawn and when to keep work inline.

## Router handoff

This workflow is meant to load **after** the top-level router has already
decided that the task is not a trivial inline-only request.

If the current session already has a routing handoff, **honor it**:

- `WORKFLOW_MODE: inline | targeted | full`
- `SCOPE_CLASS: isolated | shared | critical`
- `ROUTING_REASON: <why this mode was chosen>`

Do **not** reopen the `inline vs workflow` question when that handoff exists.
You may escalate mode with evidence, but you should not demote a routed workflow
back to inline just to save spawns.

If the user invoked `/build` directly and no handoff exists, classify now:

| Scope class | Default mode |
|---|---|
| `isolated` | `inline` |
| `shared` | `targeted` |
| `critical` | `full` |

## Mode contract

| Mode | Meaning | Default shape |
|---|---|---|
| `inline` | one-file, obvious, low-risk | main session + direct verify |
| `targeted` | bounded multi-file change | implementer + 1 reviewer + final-verifier |
| `full` | cross-cutting or high-risk | explorer + implementer + review pressure + final-verifier |

## Phase 0 — Handoff or classification

If `WORKFLOW_MODE` is already present, accept it and continue. Otherwise,
classify the scope before deciding how deep to go. Run `git diff --stat HEAD`
(or read the user's description):

- **ISOLATED**: 1 module, <=5 files, obvious change. 0-1 agent spawns.
- **TARGETED** (default): 2+ modules or unfamiliar area. 3-4 agents max.
- **FULL**: Auth, schema migration, breaking change, cross-cutting. 5-7 agents max.

## Phase 1 — Exploration (targeted/full only; skip if codebase is already understood)

If the task requires understanding unfamiliar code, spawn `workflow-explorer` with the relevant files and a concrete question. Read its synthesis. Do NOT keep reading source files in the main session.

## Phase 2 — Prompt synthesis (before implementer)

Before spawning the implementer, synthesize a condensed prompt from the raw request and any explorer output. Spawn `prompt-synthesizer` with: user request, explorer synthesis (if any), target agent type (implementer), and any constraints. Read its `PROMPT_SYNTHESIS` output.

## Phase 3 — Implementation

**MECHANICAL pre-implementation gate (no exceptions):**

```bash
git diff --name-only HEAD
```

Count the files. If you count **>1 file or any new file**: you MUST spawn
`workflow-implementer`. Do NOT proceed inline. If `WORKFLOW_MODE=inline` and
the gate fails, escalate immediately to `targeted` and continue.

| Condition | Action |
|---|---|
| 1 existing file touched, no new files | Inline Edit/Write allowed |
| >1 file OR new file created | Spawn `workflow-implementer` immediately |

After the implementer returns:
- Run `pwsh ~/.agents/tools/detect-slop.ps1 -Path . -Fix -Json`. If warning-severity findings remain, spawn `slop-refactorer`.
- Mark: `pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "implementation_done"`

## Phase 4 — Review

Spawn exactly ONE reviewer by default. Pick based on what changed:

- **New/moved files, shared types, DI wiring**: `modularity-expert`
- **Auth, HTTP, DB writes, user input, paths**: `security-reviewer`
- **Everything else**: `code-quality-reviewer`

For complex reviews (FULL tier, or when the implementer changed >5 files): spawn `prompt-synthesizer` first with the diff context and target reviewer type. Use its output as the reviewer prompt.

Spawn a second reviewer only if the first surfaces a finding outside its lane. If BLOCKING findings: re-spawn implementer with the blocking findings as deltas. Cap at 3 implementer iterations.

## Phase 5 — Verification (Iron Law)

Run the verification command inline. Capture the exact exit code. Then spawn `final-verifier` with the command output and exit code. The Iron Law forbids claiming completion without fresh exit-0 evidence.

Run writeback: `pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "<id>"`. If WARN NO WRITEBACK: update `.wiki/features.md` / `.kit/context/memory.md` or include the warning.

Mark gates: `pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "verification_evidence"` and `... -Mark "handoff_written"`.

## Phase 6 — Handoff

Write a one-paragraph summary: files changed, behavior, verification status, any open risks. Run `pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove`.
