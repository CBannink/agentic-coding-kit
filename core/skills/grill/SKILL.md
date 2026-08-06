---
name: grill
description: >-
  Resolve consequential product or engineering ambiguity through a focused
  one-question-at-a-time interview. Use only when the user explicitly asks to
  be grilled, interviewed, challenged, or helped to sharpen a specification.
---

# Grill

Inspect available repository evidence before asking about facts the agent can
resolve. Keep a compact decision record; do not begin implementation while the
interview is active.

## Loop

```text
Inspect -> Ask -> Recommend -> Incorporate -> Repeat -> Synthesize
```

Ask exactly one high-leverage decision question at a time. Explain briefly why
it changes the result, offer the materially different options, and recommend a
default with its tradeoff. Prefer concrete examples when wording is ambiguous.
Do not send questionnaires, ask for repository facts, reopen settled choices,
or prolong the interview after answers stop changing the design.

Probe, when relevant:

- beneficiary and observable outcome;
- boundaries, invariants, and explicit non-goals;
- product behavior and failure behavior;
- compatibility, migration, security, and operational tradeoffs;
- what evidence would make the result acceptable.

Stop when the user confirms the direction, asks to stop, or remaining unknowns
can be resolved during implementation without changing the contract. Return:

- agreed outcome and acceptance criteria;
- decisions and assumptions;
- explicit non-goals;
- unresolved risks or choices;
- recommended next skill: Design, Architecture, Experiment, or Build.
