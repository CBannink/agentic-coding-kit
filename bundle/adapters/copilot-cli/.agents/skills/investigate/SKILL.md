---
name: investigate
description: User-typed /investigate entry point for Copilot CLI. Runs inline in the current session, prints visible phase progress, and spawns only leaf agents. MUST BE USED when the user types `/investigate` or asks to debug, diagnose, or root-cause a problem.
---

# /investigate (Copilot CLI inline)

For Copilot CLI, the current session owns `/investigate`. Stay inline and use
the loaded Copilot instructions as the workflow contract:

- repo override: `.github/copilot-instructions.md` when present
- otherwise: `~/.copilot/copilot-instructions.md`

## Rules

- Do NOT spawn `investigate-orchestrator`.
- Emit visible phase lines before every leaf-agent spawn.
- Spawn only leaf agents, usually `workflow-explorer` for hypothesis testing.
- Keep `kit-investigate.(ps1|sh)` wrappers and direct `copilot --agent ...`
  calls as explicit fallback entrypoints, not the default slash path.

## Minimum fallback if the matching `/investigate` section is unavailable

1. Capture the symptom in one sentence.
2. Rank 3-5 hypotheses and design the cheapest distinguishing tests.
3. Spawn 1-3 `workflow-explorer` runs for the strongest hypotheses.
4. Converge on the supported root cause and write a Build Brief.
