---
description: User-typed /investigate entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates, decides mode, and spawns only leaf agents via the Task tool.
---

# /investigate

You are the main Claude Code / OpenCode session. The user invoked /investigate because they want to debug, diagnose, root-cause an unknown failure. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Run hypothesis-driven investigation. You ARE the orchestrator. Output is evidence + a Build Brief — NO code changes in this workflow.

## Discipline

1. State the symptom precisely (one sentence).
2. List 3-5 competing hypotheses ranked by prior likelihood.
3. For each hypothesis, design the cheapest test that distinguishes it.
4. Run the cheapest test first.
5. Eliminate hypotheses with evidence — file:line, log excerpt, command output.
6. Stop when ONE hypothesis is supported by direct evidence.

## Phase 1 — Symptom capture

Read what the user said. Read referenced files/logs/errors. Read `.kit/context/memory.md` if present for prior known issues. Restate symptom in one sentence and confirm with one clarifying question if needed.

## Phase 2 — Hypothesis exploration (parallel)

Spawn 1-3 `workflow-explorer` subagents in parallel via simultaneous Task calls. Each gets ONE hypothesis and a single cheap test (read file X / grep pattern Y / `git log -p` over file Z).

## Phase 3 — Convergence or new hypothesis

- One hypothesis supported, others eliminated → root cause confirmed → Phase 4.
- No hypothesis supported → 1-2 new hypotheses based on what explorers learned, repeat Phase 2.
- Multiple supported → document each.

## Phase 4 — Build Brief writeback

Write to `${AGENTS_SESSION_ROOT}/{session_id}/handoffs.md` (default `.kit/session-state/{session_id}/handoffs.md` in a bootstrapped repo):

```
## Build Brief [YYYY-MM-DD]
- **Symptom**: <one sentence>
- **Root cause**: <one sentence with file:line>
- **Evidence**: <bullet list of cites>
- **Recommended fix**: <one sentence — what /build should change>
- **Out of scope**: <what NOT to fix in the same change>
```

The next /build invocation picks this up via `brief-resolver.ps1`.

## Phase 5 — User summary

Return: root cause in one sentence, smoking-gun evidence, recommendation ("Run /build" OR "config/infra issue").

## What NOT to do

- Do NOT edit code. Even one line. The contract is "evidence only".
- Do NOT keep exploring after root cause is confirmed.
## Phase 5c — Reflect trigger (mechanical)

Check `~/.agents/context/reflections.md` length. If 5+ unaddressed entries: spawn the `reflect` skill via the Skill tool (or surface to user "5+ workflow reflections accumulated, recommend running /reflect"). Mechanical, not vibes.
