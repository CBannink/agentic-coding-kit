---
name: design
description: >-
  Produce or review a feature, architecture, or UI design before implementation,
  using current repository evidence, material options, an explicit Design
  Contract, independent review, and optional Sage challenge; transition into
  build in the same main session when implementation is requested.
---

# Design

Keep the main session as orchestrator and choose one playbook:

- `INLINE DESIGN`: inspect current reality, draft and validate the design
  directly, then return it or transition into build.
- `REVIEWED DESIGN`: use a targeted Scout only when discovery is useful, draft
  the appropriate Design Contract, obtain independent review, optionally use
  Sage for a difficult judgment, revise, then return or transition into build.

These are playbooks, not mandatory pipelines. Establish the desired outcome and
smallest relevant wiki context, present options only where a real choice exists,
and reassess after every result. Every Scout, reviewer, Sage, browser, or UI
Critic returns to the main orchestrator; none dispatches its successor.

For implemented UI design, conditionally capture a browser baseline, implement,
capture required target states, and have UI Critic compare them with the UI
Design Contract or supplied reference. Route concrete deltas back through the
orchestrator. Browser/visual work shares the build repair budget: count a cycle
only after a completed repair fails its next applicable gate, and stop for user
direction after two failed repaired results.

Load only the applicable contract reference:

- [feature.md](references/feature.md) for behavioral/product design.
- [architecture.md](references/architecture.md) for component and system design.
- [ui.md](references/ui.md) for visual/interaction design and browser loops.
