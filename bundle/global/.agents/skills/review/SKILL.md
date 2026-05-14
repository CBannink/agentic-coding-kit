---
name: review
description: User-typed /review entry point. Spawns the `review-orchestrator` subagent via the Task tool so the kit's full phased pipeline runs (surface review parallel, adversarial pass, false-positive verify). MUST BE USED when the user types `/review` or asks to review, audit, check quality, find bugs. Use PROACTIVELY rather than running the workflow inline.
---

# /review

Spawn the `review-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator handles every phase (surface review parallel, adversarial pass, false-positive verify) and returns when done.

## Action

Use the Task tool now. `subagent_type` = `review-orchestrator`. `description` = `review workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## What you DO NOT do

- Do NOT run the workflow inline. The orchestrator's body is the canonical pipeline — running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks small. `review-orchestrator` will classify scope (ISOLATED / SHARED / CRITICAL) and pick the right depth itself.
- Do NOT spawn other subagents directly from this skill. The orchestrator does the fan-out.