---
name: migrate
description: Plan or verify a persisted-data, schema or mixed-version rollout change.
---
# Data and rollout changes
Use this only when schema, persisted data or deployment ordering changes, not for every query. Establish current data assumptions, old and new readers/writers, rollout order, reversibility and ownership of the migration.

Check compatibility during mixed-version operation. Consider locking, backfill size, defaults, uniqueness and partial completion where relevant. Define what happens after interruption and whether rerunning is safe. Rehearse on an authorized representative fixture or dry-run whose real effects are understood.

Record the verification evidence and rollback or forward-recovery limits. Do not describe a destructive migration as reversible merely because a down function exists. Never run against production or modify real data without explicit authority.

One worker owns the migration and its shared artifacts. Dependent workers consume the agreed contract and integrated baseline. A reviewer discovering a data-safety problem returns it to the owner; it is not an opportunistic micro-fix.
