---
name: backend
description: "Implement or review backend boundaries, persistence, failure behavior and API contracts without speculative architecture."
---

# Backend

Trace the relevant request or job to its domain behavior, storage and external effects. Read the existing contract, ownership rules and verification recipe. Keep the established framework and deployment shape. A small endpoint does not justify microservices, a generic repository layer, a message bus or a new dependency-injection framework. Add a seam only when it hides meaningful complexity or separates a real external dependency.

Validate at trust boundaries and enforce authorization on the server for the actual actor and resource. Preserve tenant filtering through reads, writes, caches and background jobs. Never trust a client-supplied role or tenant as authorization. Keep secrets and sensitive payloads out of responses and diagnostic logs.

Make persistence and failure semantics explicit: transaction ownership, rollback, uniqueness, ordering and the point an external effect occurs. Do not assume a database rollback undoes a sent email or remote request. Retries require a safe failure classification and an idempotency policy; an in-memory duplicate check is not automatically durable or concurrent-safe. Bound timeouts, payloads, pagination, concurrency and connections where relevant. Inspect expensive query behavior before adding caches or indexes; preserve parameterization and access controls.

Keep public errors compatible and useful without leaking internals. Maintain the source of truth for schemas/types instead of several hand-synchronized DTO copies. Observe failures with existing structured logging and correlation conventions, not silent fallbacks that manufacture success. Changes to authorization, migrations or shared-state semantics require the owner's existing boundary approval.

Run focused contract/integration tests against appropriate isolated fixtures. Cover the changed failure path and, where applicable, wrong-tenant access, duplicates, rollback or concurrent updates. Do not claim atomicity or performance from unit tests alone. Report the real commands, environment, effects and gaps through the standard handoff. Prefer an installed repository/database skill for version-specific detail rather than loading a generic architecture catalog.
