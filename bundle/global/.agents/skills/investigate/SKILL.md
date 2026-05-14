---
name: investigate
description: User-typed /investigate entry point. Spawns the `investigate-orchestrator` subagent via the Task tool so the kit's full phased pipeline runs (symptom -> hypotheses -> cheapest test -> evidence -> Build Brief). MUST BE USED when the user types `/investigate` or asks to debug, diagnose, root-cause, why-is-X-broken. Use PROACTIVELY rather than running the workflow inline.
---

# /investigate

Spawn the `investigate-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator handles every phase (symptom -> hypotheses -> cheapest test -> evidence -> Build Brief) and returns when done.

## Action

Use the Task tool now. `subagent_type` = `investigate-orchestrator`. `description` = `investigate workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## What you DO NOT do

- Do NOT run the workflow inline. The orchestrator's body is the canonical pipeline — running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks small. `investigate-orchestrator` will classify scope (ISOLATED / SHARED / CRITICAL) and pick the right depth itself.
- Do NOT spawn other subagents directly from this skill. The orchestrator does the fan-out.