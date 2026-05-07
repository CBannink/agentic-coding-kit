---
name: build
description: User-typed /build entry point. Spawns the `build-orchestrator` subagent via the Task tool so the kit's full phased pipeline runs (scope, explore, implement, review, verify). MUST BE USED when the user types `/build` or asks to implement, fix, refactor, change, add, modify code. Use PROACTIVELY rather than running the workflow inline.
---

# /build

Spawn the `build-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator handles every phase (scope, explore, implement, review, verify) and returns when done.

## Action

Use the Task tool now. `subagent_type` = `build-orchestrator`. `description` = `build workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## What you DO NOT do

- Do NOT run the workflow inline. The orchestrator's body is the canonical pipeline — running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks small. `build-orchestrator` will classify scope (ISOLATED / SHARED / CRITICAL) and pick the right depth itself.
- Do NOT spawn other subagents directly from this skill. The orchestrator does the fan-out.