# Architecture Design Contract

Cover the problem and forces, current architecture, chosen direction,
boundaries/responsibilities, and data/control flow. Make interface invariants,
errors, configuration, and material performance characteristics explicit.

Prefer leverage and locality: a change should solve the problem near its owner
without forcing pass-through layers. Apply a deletion/pass-through test: if a
new abstraction can disappear or merely relays another interface, justify why
it exists. Preserve stable public test seams rather than exposing internals for
tests. Include reliability/observability, relevant security/privacy,
compatibility/migration, verification, and accepted tradeoffs. Present
alternatives only when their consequences could change the decision; these are
reasoning aids, not mandatory vocabulary.
