---
name: plan
description: User-typed /plan entry point. Spawns the `plan-orchestrator` subagent via the Task tool so the kit's full phased pipeline runs (clarify, explore, pressure-test, plan.md, approval gate). MUST BE USED when the user types `/plan` or asks to plan, spec, design, scope a change. Use PROACTIVELY rather than running the workflow inline.
---

# /plan

Spawn the `plan-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator handles every phase (clarify, explore, pressure-test, plan.md, approval gate) and returns when done.

## Action

Use the Task tool now. `subagent_type` = `plan-orchestrator`. `description` = `plan workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## What you DO NOT do

- Do NOT run the workflow inline. The orchestrator's body is the canonical pipeline — running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks small. `plan-orchestrator` will classify scope (ISOLATED / SHARED / CRITICAL) and pick the right depth itself.
- Do NOT spawn other subagents directly from this skill. The orchestrator does the fan-out.