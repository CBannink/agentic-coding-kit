---
name: design
description: >-
  Design or review a feature, UI, prototype, or consequential product decision
  before implementation.
---

# Design

Keep the primary as orchestrator. Resolve repository facts before asking the
user and present choices only when their consequences change implementation.

## INLINE DESIGN

```text
Inspect -> Decide -> Validate
```

Use for clear, bounded design work, then return the design or transition to
Build when implementation is authorized.

## DESIGN LOOP

```text
Frame -> Explore -> Collaborate -> Decide -> Validate
```

Frame the beneficiary, current reality, desired outcome, constraints,
acceptance, and non-goals. Use bounded exploration only when it reduces
uncertainty. Ask one to three consequential questions at a time with a
recommended default; stop when further answers would not change the design.
Validate through source inspection, one disposable prototype, or a targeted
independent challenge. Comparative variants belong to Experiment. Production
promotion returns through Build.

## UI STUDIO

```text
Brief -> Baseline -> Direction -> Build -> Capture -> Critique -> Refine
```

Define three to five observable criteria and one coherent visual direction.
Use one writer. Capture representative states rather than every viewport.
Browser QA proves behavior and state; UI Critic judges hierarchy, coherence,
usability, and polish and returns at most three important contract-linked
deltas. Normally allow at most two refinement cycles; stop earlier when criteria
are met and stop on plateau or a missing product choice.

Load only the applicable contract:

- [feature.md](references/feature.md) for product behavior.
- [ui.md](references/ui.md) for UI Studio.
- [prototype.md](references/prototype.md) for one disposable question.

Use Architecture for repository structure and Grill for an explicitly
intensive interview.
