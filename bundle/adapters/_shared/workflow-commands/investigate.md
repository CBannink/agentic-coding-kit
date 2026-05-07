---
description: User-typed entry point for investigate-orchestrator. Spawns the orchestrator subagent which runs the full phased pipeline.
---

# /investigate

You are running on __HOST_NAME__ via the kit's shared workflow-commands.

This slash command is a thin entry point. The actual workflow lives in the
`investigate-orchestrator` subagent at `__SKILL_ROOT__/../agents/investigate-orchestrator.md` (Claude Code) or
the equivalent location for OpenCode / Copilot CLI.

## Action

Spawn the `investigate-orchestrator` subagent via the Task tool with the user's request as
the prompt. The orchestrator handles every phase (scope, exploration,
implementation/review/verify, handoff). Do NOT inline the workflow here --
that defeats the description-routing pattern that makes the kit work.

The orchestrator's `description:` is sticky enough that on most user
prompts auto-routing will fire it BEFORE this slash command even runs.
This file exists so users who explicitly type `/investigate` reach the same
endpoint.