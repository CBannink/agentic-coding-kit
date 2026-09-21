---
name: async
description: Check cancellation, retries, concurrent state, cleanup and idempotency.
---
# Async and shared-state changes
Write down the invariant, who owns the state, relevant lifecycle transitions and what can interleave. Inspect callers, cleanup and failure paths. Distinguish a local ordering issue from cross-process coordination.

Consider duplicate events, late responses, cancellation, partial failure and stale state only where the actual design admits them. For retries, establish idempotency and which effects can already have happened. For shared promises or locks, verify release on success, error and cancellation. Do not introduce a new concurrency policy as a 'small cleanup'.

Test the meaningful interleaving using a controlled harness where practical; timing sleeps are weak evidence. A sequential passing test does not prove a race is fixed. Explain the tested order and remaining gaps.

A worker can repair a local implementation within an agreed policy. Changing ownership, transaction semantics or a shared lifecycle requires the owner. A reviewer self-edit touching these semantics normally needs independent scrutiny, even if the diff is one line.
