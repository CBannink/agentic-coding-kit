---
name: pr-ready
description: >-
  Review, repair, verify, and package a working-tree or commit-range diff for a
  human pull request.
---

# PR Ready

Keep the primary as orchestrator. Establish the base, exact diff, workspace
baseline, changed behavior, affected consumers, and applicable wiki sections.
Historical review guidance is evidence, not authority; this skill never edits
`.wiki`.

For a small obvious diff, inspect, run proportionate checks, and package it
directly. Otherwise use the primary's LOOP with one combined goal-first review
and bounded repair. Split review modes or add test, security, browser, or UI
specialists only for a concrete risk or missing proof.

Select review concerns only from the goal, diff, repository rules, or failed
evidence. Do not run a universal checklist.

Use [history.md](references/history.md) for curated historical practices and
[report.md](references/report.md) for the result. Return `PR READY`,
`NEEDS DECISION`, or `BLOCKED` with a suggested title and description, repaired
and remaining material findings, fresh evidence, risks, and useful human-review
attention areas.
