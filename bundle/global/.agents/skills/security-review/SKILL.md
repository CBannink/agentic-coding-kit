---
name: security-review
description: User-typed /security-review entry point. Spawns the `security-review-orchestrator` subagent via the Task tool so the kit's full phased pipeline runs (authorization, parallel attack-class fan-out, false-positive verify, synthesis). MUST BE USED when the user types `/security-review` or asks to security audit, pentest, vulnerability scan, OWASP. Use PROACTIVELY rather than running the workflow inline.
---

# /security-review

Spawn the `security-review-orchestrator` subagent via the **Task tool** with the user's verbatim request as the prompt. The orchestrator handles every phase (authorization, parallel attack-class fan-out, false-positive verify, synthesis) and returns when done.

## Action

Use the Task tool now. `subagent_type` = `security-review-orchestrator`. `description` = `security-review workflow`. `prompt` = the user's verbatim request plus any clarifying context they supplied.

## What you DO NOT do

- Do NOT run the workflow inline. The orchestrator's body is the canonical pipeline — running phases here in the main session defeats the design.
- Do NOT skip the Task spawn even if the request looks small. `security-review-orchestrator` will classify scope (ISOLATED / SHARED / CRITICAL) and pick the right depth itself.
- Do NOT spawn other subagents directly from this skill. The orchestrator does the fan-out.