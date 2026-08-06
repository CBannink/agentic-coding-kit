---
name: analyze
description: >-
  Analyze or diagnose repository behavior, architecture, dependencies, product,
  or performance without changing code or tests.
---

# Analyze

Remain read-only and answer the exact question from the smallest relevant
repository and wiki context.

## INLINE ANALYSIS

```text
Question -> minimum discriminating evidence -> answer
```

Use for bounded explanations and direct diagnosis.

## ANALYSIS LOOP

```text
Anchor question -> bounded investigations -> integrate -> discriminate -> conclude
```

Use when noisy exploration, competing hypotheses, or independent axes justify
fresh contexts. Dispatch the smallest bounded investigation set and add another
only for a genuinely independent question. The primary synthesizes facts,
inferences, material uncertainty, recommendation, and the cheapest useful next
check. Include counterarguments and falsifiers only when the decision is
consequential.

For diagnosis, capture the symptom, reproduction, small hypothesis set,
cheapest discriminating probes, demonstrated cause, affected paths, and repair
and verification route. Transition to Build only when implementation is
requested.

## Focus

- **Code:** trace observable behavior through entry points, callers, state,
  side effects, errors, and tests. Separate source facts from inferred runtime
  behavior; use a small executable check when ambiguity matters.
- **Architecture:** map only relevant boundaries, ownership, dependency
  direction, data/control flow, reliability, migration, and verification
  forces. Compare materially different options and name the cheapest
  discriminating experiment.
- **Dependency or platform:** use current primary documentation for unstable
  facts. Assess fit, maintenance, compatibility, migration cost, operational
  risk, and licensing when material. Distinguish repository facts from external
  facts and prefer a reversible trial.
- **Performance:** start from a measured symptom and workload. Identify the
  critical path, instrument the cheapest useful signal, compare hypotheses,
  and avoid speculative micro-optimization.
- **Diagnosis:** establish a red-capable signal, minimize only when useful,
  rank a few falsifiable hypotheses, and run the cheapest probe that separates
  them. Inspect new evidence before proposing repair. Classify ownership and
  conclude with: stop, gather one missing signal, or transition to Build.
