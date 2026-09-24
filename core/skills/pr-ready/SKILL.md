---
name: pr-ready
description: >-
  Review, repair, verify, and package a working-tree or commit-range diff for a
  human pull request.
---

# PR Ready

This skill loads lazily through its native trigger. The router loads only the
skill each request needs, when it is needed; this body is never preloaded or
embedded in assignments.

Keep the primary as orchestrator. Establish the base, exact diff, workspace
baseline, changed behavior, affected consumers, and applicable wiki sections.
Historical review guidance is evidence, not authority; this skill never edits
`.wiki`.

For a small obvious diff, inspect, run proportionate checks, and package it
directly. For a broad diff, work in three passes.

1. Map. Build a PR map of the diff: every changed path, which paths work
together, and which feature or functionality each group implements. One
feature per unit; a unit may span an implementation plus its directly
corresponding test. Map inline for a small diff; for a broad one use a
single reviewer to produce the map. Drop units with no meaningful content
and never assign one path to two units.
2. Scan. Fan out one read-only `simple-reviewer` per feature unit with its
assigned paths, the base, and exactly one concern grounded in that feature:
bug risk, or maintainability — needless properties and abstractions, endless
branching, duplicated logic; less code is better to maintain. Unit reviewers
run on the cheap fast tier and judge only their unit: no whole-diff claims,
no universal checklist, no other unit's findings.
3. Decide. The primary collects unit reports as leads, not verdicts: check
each against live source, reconcile cross-feature implications, deduplicate
root causes, then repair and run the normal fresh whole-diff `reviewer` as
the authoritative gate. Split other review modes or add test, security,
browser, or UI specialists only for a concrete risk or missing proof.

Select review concerns only from the goal, diff, repository rules, or failed
evidence. Do not run a universal checklist.

Use [history.md](references/history.md) for curated historical practices and
[report.md](references/report.md) for the result. Return `PR READY`,
`NEEDS DECISION`, or `BLOCKED` with a suggested title and description, repaired
and remaining material findings, fresh evidence, risks, and useful human-review
attention areas. Never dispatch a successor.
