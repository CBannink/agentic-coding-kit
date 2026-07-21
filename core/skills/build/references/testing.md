# Testing Policy

The coder adds or updates tests only when they are useful durable evidence of
requested behavior or a practical regression guard. Static inspection alone
may establish non-behavioral work. Behavioral changes require executable
evidence when feasible; when infeasible, record why and disclose remaining
risk. For a clear bug, reproduce the failure before repair when practical and
preserve a regression test when it has lasting value.

The independent Test Engineer is always conditional. Use one only when an
independent perspective has a specific high-value gap to investigate.

Before inspecting internals, the Test Engineer writes:

```markdown
# Independent Test Charter
## Contract behaviors
## Existing evidence
## Highest-value gaps
## Chosen test level
```

Prefer unit for pure behavior, integration/contract for a real boundary, and
E2E for a critical user flow. Target boundaries, invalid/empty input, error
propagation, transitions, ordering/concurrency, compatibility, permissions,
and partial failure. Review test-only deltas for behavioral fidelity, realistic
fixtures, determinism, and excessive implementation coupling.

Use independent hardening when meaningful behavior changed and a fresh,
independent test perspective has real expected value. Skip it for demonstrably
non-behavioral work or a tightly bounded change already established by
proportionate independent executable evidence; record the reason when the skip
is not obvious. A Test Engineer report returns only to the orchestrator and
never dispatches a coder or reviewer.
