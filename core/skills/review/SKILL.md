---
name: review
description: >-
  Independently review a working tree, commit range, branch, contract and
  implementation, design, test-only delta, subsystem, or migration plan using
  evidence-backed findings and dynamically selected correctness, architecture,
  testing, failure, compatibility, migration, performance, or security lenses.
---

# Review

Establish target and base. Read applicable instructions and exact wiki
invariants, inspect the target independently, and run cheap read-only checks
when useful. Select only relevant lenses. Return failure-mode findings with
locations, evidence, affected contract/invariant, minimum correction, severity,
and confidence. Separate blocking/important defects from optional improvements;
explicitly state when none exist.

Available lenses: [correctness](lenses/correctness.md),
[architecture](lenses/architecture.md), [test quality](lenses/test-quality.md),
[silent failure](lenses/silent-failure.md),
[compatibility](lenses/compatibility.md), [migration](lenses/migration.md),
[performance](lenses/performance.md), and [security](lenses/security.md).
