---
name: analyze-workflow
description: Use when the user says /analyze or asks to research, compare, investigate, or evaluate with multiple perspectives. Supports repo-local augmentation from AGENTS.md, CLAUDE.md, GEMINI.md, and .kit/workflows/analyze.md.
---

# Analyze Workflow

## Load Context First

Before analysis, read these files when they exist:
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `.kit/workflows/shared.md`
- `.kit/workflows/analyze.md`
- `.kit/context/memory.md`
- `.kit/context/handoffs.md`

## Default Agent Matrix

### Explore

- `architecture-explorer`
  Purpose: map structure, boundaries, and moving parts.
- `surface-explorer`
  Purpose: inspect APIs, capabilities, interfaces, and dependencies.
- `risk-explorer`
  Purpose: identify trust boundaries, safety concerns, and failure modes.
- `ops-explorer`
  Purpose: inspect performance, operational, adoption, or workflow impact when relevant.

### Theorize

- `pragmatist`
  Purpose: recommend the lowest-risk workable path.
  Source bias: senior engineer execution realism.
- `skeptic`
  Purpose: challenge assumptions and expose weak reasoning.
  Source bias: gstack hard-nosed review style.
- `security-reliability`
  Purpose: analyze trust boundaries, resilience, and production risk.
  Source bias: gstack review specialists.
- `product-wedge`
  Purpose: frame the user problem, wedge, and status-quo replacement when applicable.
  Source bias: gstack `office-hours`.

### Verify

- `claim-verifier`
  Purpose: verify disputed or important claims against code, docs, tests, or data.

## Prompt Catalog

Default role prompts live under:
- `plugins/caspar-workflows/prompts/analyze/`

## Workflow

1. Explore with 2-4 parallel fact-finding agents.
2. Synthesize findings into a shared evidence packet.
3. Theorize with at least 2 perspective agents arguing from different trade-offs.
4. Identify agreement, disagreement, and blind spots.
5. If the topic is product direction, architecture before coding, or wedge selection, include `product-wedge` and use gstack `office-hours` style pressure.
6. If blind spots are material, run targeted exploration and re-synthesize.
7. Verify testable claims against code, docs, or direct evidence when needed.
8. If the analysis confirms stable repo facts, update `.kit/context/memory.md`.
9. If the analysis changes what the next session should do, update `.kit/context/handoffs.md`.

## Rules

- Never skip the explore phase for non-trivial analysis.
- Present disagreements instead of silently picking a winner.
- Keep facts separate from recommendations.
- Cite concrete evidence in the final synthesis.
- Use gstack `investigate` principles instead of generic analysis when the task is really root-cause analysis.
- Use gstack `plan-eng-review` principles when the analysis is about architecture readiness.
- Write only durable facts to `memory.md`.
- Use `handoffs.md` for current status, next steps, blocked paths, and incomplete investigations.

## Repo-Local Augmentation Contract

Repo-local analyze instructions may define:
- Mandatory perspectives
- Additional research angles
- Preferred source hierarchy
- Required verification steps
- Domain-specific judges or veto roles
- Extra rules for what may be promoted into `memory.md`
