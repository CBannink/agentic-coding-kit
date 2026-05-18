---
name: investigate
description: Use when the user asks to debug, diagnose, root-cause, or figure out why something is broken. Runs symptom capture, hypothesis generation, parallel evidence gathering, convergence, Build Brief output.
---

# /investigate

Root-cause-first debugging. Do NOT fix code — only produce a Build Brief with the root cause and recommendation.

## Phase 1 — Symptom capture

Restate the symptom in ONE sentence. Read any relevant logs, error messages, or reproduction steps the user provided. If the symptom is ambiguous, ask ONE clarifying question, then assume and proceed.

## Phase 2 — Hypotheses

List 3-5 hypotheses ranked by prior likelihood. For each hypothesis, design the cheapest distinguishing test (a single command, a targeted file read, a grep pattern).

## Phase 3 — Parallel evidence gathering

Spawn 1-3 `workflow-explorer` agents in parallel. Each gets ONE hypothesis and the cheapest test design. Do NOT serialize hypotheses — run them in parallel so evidence arrives simultaneously.

## Phase 4 — Convergence

- **One hypothesis supported, others eliminated**: proceed to Phase 5.
- **No hypothesis supported**: form 1-2 new hypotheses and repeat Phase 3. Cap at 3 rounds total.
- **Multiple hypotheses supported**: document each with evidence weight.

## Phase 5 — Build Brief

Write to the session handoff path:
```
## Build Brief [YYYY-MM-DD]
- Source: investigate
- Symptom: <one sentence>
- Root cause: <file:line>
- Evidence: <bullets with file:line citations>
- Recommended fix: <one sentence>
- Out of scope: <what NOT to fix>
```

Read `.kit/context/memory.md` when it exists. If a stable architectural fact about the root cause was confirmed, update it.

## What you DO NOT do

- Do NOT edit code. investigate produces evidence, not fixes.
- Do NOT keep exploration inline. Spawn `workflow-explorer` for every hypothesis test.
- Do NOT claim a root cause without file:line evidence for the defect owner AND at least one nearby plausible file checked and ruled out.
