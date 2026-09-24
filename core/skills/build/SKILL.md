---
name: build
description: >-
  Implement an authorized change through outcome, acceptance, authority, and
  verification, a builder-owned check-repair loop, independent review, and
  bounded delta repair.
---

# Build

Use only in the primary session. Load this skill only when implementation is requested; plan/design-only work stops before implementation. The primary owns request interpretation, routing, evidence reconciliation, and completion. Specialists do not orchestrate or load this skill.

## Prepare

Understand the user request, inspect Git state and relevant live source, and preserve unrelated work. When the needed files are unknown, dispatch one focused Repo Scout first — even when you expect to implement inline; it reports repository facts and starting paths, never the solution. Read the returned files yourself; read inline directly only when you already know exactly what is needed. Explore the ownership, current behavior, repository patterns, likely tests, and generated boundaries needed for a reliable plan.

Define outcome, acceptance, authority, and verification. For loop-driven or multi-agent work, the primary writes exactly three shared objects plus a compact RELEVANT FILES map of starting paths with one-line summaries:

```text
GOAL
One clear outcome and purpose.

ACCEPTANCE
1. Numbered, observable criterion.

PLAN
Complete repository-grounded implementation and verification approach, including authority and scope boundaries and how each criterion will be proven.
```

These plus the files map are the shared assignment objects for loop work. Do not add separate shared sections for decisions, proof, Scout facts, constraints, or repository summaries. Keep GOAL, ACCEPTANCE, and PLAN unchanged through implementation, testing, review, and repair. For a simple single-agent task, send a short outcome, scope, and proof request instead of the full contract.

INLINE whenever you already hold the context, contract, and proof: implement directly through this skill, verify, and stop. Substantive changes, including INLINE work, still require an independent review unless an explicit project or user policy exempts them.

## Implement and verify

Dispatch one Coder per goal with only the unchanged GOAL, ACCEPTANCE, and PLAN. The Coder owns its local inspect–implement–check–repair loop within scope and adapts ordinary implementation details when current source requires it. It must not change GOAL or ACCEPTANCE and must report any material PLAN departure. Routine failing assertions are the Coder's loop, not owner handoffs.

After the Coder returns, freeze the stable live diff as the candidate. Reconcile its reported evidence against the actual changed files, scope, and generated boundaries. Missing decisive evidence for important changed behavior blocks. Relevant failures block unless reproduced on the untouched base or equivalently isolated.

Use a Test Engineer only when an important acceptance criterion lacks convincing durable proof. Give it the same unchanged three objects. It adds only tests the Coder did not write, and only for major end functionality or backend functions at risk—never a broad matrix, incidental-wording checks, duplicated coverage, or reinterpreted requirements. The two never write the same test. It supplements rather than replaces builder evidence and the Reviewer.

Dispatch a fresh Reviewer with the unchanged three objects after verification. It independently reads the live diff and complete changed files and records PASS or BLOCKED for every acceptance criterion. Missing decisive evidence for important changed behavior is BLOCKED.

## Repair

The primary validates findings and rejects preferences, speculative edges, optional cleanup, invented stronger requirements, and scope-expanding fixes. Send the reviewer's finding verbatim — file and line, what is wrong, evidence, minimum fix — to the repair Coder with the same unchanged GOAL, ACCEPTANCE, and PLAN, plus the files it owns and the checks it must re-run. Freeze the new candidate after repair. Then the Reviewer rechecks; the complete GOAL and every ACCEPTANCE criterion stay in scope, not only prior findings.

Bound repair to two unsuccessful attempts for the same material failure. Stop and report the evidence when the bound is reached. Complete only after decisive evidence covers the final candidate and a full-scope review PASS.
