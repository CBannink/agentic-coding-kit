---
name: redesign
description: User-typed /redesign entry point. Spawns the `redesign-orchestrator` subagent via the Task tool so the kit's full phased pipeline runs (aesthetic-lock, capture, per-component design, implement, visual-diff). MUST BE USED when the user types `/redesign` or asks to greenfield UI, multi-component visual redesign, fresh design. Use PROACTIVELY rather than running the workflow inline.
---

# /redesign

Spawn the `redesign-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator handles every phase (aesthetic-lock, capture, per-component design, implement, visual-diff) and returns when done.

## Action

Use the Task tool now. `subagent_type` = `redesign-orchestrator`. `description` = `redesign workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## What you DO NOT do

- Do NOT run the workflow inline. The orchestrator's body is the canonical pipeline — running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks small. `redesign-orchestrator` will classify scope (ISOLATED / SHARED / CRITICAL) and pick the right depth itself.
- Do NOT spawn other subagents directly from this skill. The orchestrator does the fan-out.