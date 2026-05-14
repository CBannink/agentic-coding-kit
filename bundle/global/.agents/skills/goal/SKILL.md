---
name: goal
description: "User-typed /goal entry point. Classifies the stated goal (CODE / DESIGN / INVESTIGATION / REFACTOR / BOOTSTRAP / MULTI / PR_REVIEW) and routes to the correct kit workflow end-to-end via the goal-orchestrator subagent. MUST BE USED when the user types `/goal` or says 'achieve this autonomously', 'drive this to completion', or 'iterate until done'. Use PROACTIVELY rather than running the workflow inline."
---

# /goal

Spawn the `goal-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator classifies the goal type, picks the correct kit workflow as the primary pipeline, and iterates until the goal is provably achieved or hits a guarded cap.

## Action

Use the Task tool now. `subagent_type` = `goal-orchestrator`. `description` = `goal workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## Goal type routing

| Goal type | Primary pipeline |
|-----------|-----------------|
| CODE | `/build` |
| DESIGN | `/redesign` |
| INVESTIGATION | `/investigate` |
| REFACTOR | `/refactor` |
| BOOTSTRAP | `/bootstrap-harness` |
| MULTI | decompose → route each sub-goal |
| **PR_REVIEW** | **see below** |

### PR_REVIEW routing

When the goal is to review a pull request or audit a branch diff, use the kit's
`pr-reviewer` agent (available on all supported hosts). Return a structured review
with `PR_REVIEW: <APPROVE|REQUEST_CHANGES|COMMENT>` at the top and Blocking /
Non-blocking / Nits / Praise sections.

## What you DO NOT do

- Do NOT run the workflow inline. The goal-orchestrator's body is the canonical pipeline -- running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks simple. `goal-orchestrator` will triage simple tasks to `/build` immediately.
- Do NOT spawn other subagents directly from this skill. The goal-orchestrator does the fan-out and workflow routing.
