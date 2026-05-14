---
name: refactor
description: User-typed /refactor entry point. Spawns the `refactor-orchestrator` subagent via the Task tool so the kit's full phased pipeline runs (principle, consequence-trace, implement, behavior-equivalence, modularity, iron-law). MUST BE USED when the user types `/refactor` or asks to refactor, restructure, clean up, consolidate, DRY/SOLID. Use PROACTIVELY rather than running the workflow inline.
---

# /refactor

Spawn the `refactor-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator handles every phase (principle, consequence-trace, implement, behavior-equivalence, modularity, iron-law) and returns when done.

## Action

Use the Task tool now. `subagent_type` = `refactor-orchestrator`. `description` = `refactor workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## What you DO NOT do

- Do NOT run the workflow inline. The orchestrator's body is the canonical pipeline — running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks small. `refactor-orchestrator` will classify scope (ISOLATED / SHARED / CRITICAL) and pick the right depth itself.
- Do NOT spawn other subagents directly from this skill. The orchestrator does the fan-out.