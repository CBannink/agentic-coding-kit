---
name: review
description: >-
  Independently review a diff, branch, contract, design, test delta, subsystem,
  or migration plan with evidence-backed findings.
---

# Review

Establish target and base. Read applicable instructions and exact wiki
invariants, inspect the target independently, and run cheap read-only checks
when useful.

- `COMBINED`: verify goal and acceptance first; inspect quality only after pass.
- `GOAL`: check requested outcome, preservation, and proof.
- `QUALITY`: check concrete correctness and maintainability risks.

Map each acceptance criterion to observable evidence or its implementation path,
and inspect the full diff for accidental dependency or generated-file churn.

Return at most three material failure-mode findings with location, evidence,
affected contract/invariant, minimum correction, severity, and confidence.
Reject speculative requirements, implausible edge cases, and style preference.
State `PASS` when no material finding exists. Select only relevant lenses.

Available lenses: [correctness](lenses/correctness.md),
[architecture](lenses/architecture.md), [test quality](lenses/test-quality.md),
[silent failure](lenses/silent-failure.md),
[compatibility](lenses/compatibility.md), [migration](lenses/migration.md),
[performance](lenses/performance.md), and [security](lenses/security.md).
