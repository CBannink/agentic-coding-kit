# Workflow Matrix

## Execution modes

| Mode | Use when | Shape |
|---|---|---|
| `INLINE` | A minimal task whose implementation context, behavioral contract, and direct proof are already present before routing | Inspect → Change/Answer → Verify → Stop |
| `LOOP` | Discovery or implementation would consume substantial primary context, spans distinct responsibilities or contracts, or benefits from fresh judgment | Anchor → Partition → dispatch before production edits → Integrate/Verify → fresh Reviewer → bounded fresh repair |

The active host session is the only orchestrator. LOOP nodes are conditional and
form a compact execution map, not a mandatory workflow engine. One production
writer is the default; up to three Coders are allowed only for fixed contracts
and disjoint write sets. Children never dispatch successors or get reactivated
after completion.

## Skills

| Skill | Use when | Main output |
|---|---|---|
| `build` | Production repository change | coherent diff and fresh proof |
| `design` | Product, prototype, or UI decision | validated design or Build handoff |
| `architecture` | Boundary, ownership, dependency, or maintainability decision | repository-grounded design and Build handoff |
| `grill` | Explicit request for an intensive decision interview | agreed contract and open decisions |
| `analyze` | Read-only explanation, diagnosis, or decision | evidence-backed conclusion |
| `review` | Independent judgment | material findings or pass |
| `pr-ready` | Human PR preparation | repaired, verified PR packet |
| `threat-model` | Material trust boundary | attack paths, controls, residual risk |
| `wiki` | Explicit repository knowledge init/reinit/audit | source-backed repository index |
| `experiment` | Controlled comparison of variants | `A`, `B`, or `INCONCLUSIVE` |

## Default LOOP realization

```text
Explore when needed
→ primary plan
→ one coherent writer, or a few safely partitioned writers
→ targeted executable proof
→ combined goal-first review
→ bounded repair and fresh proof
```

For consequential work, split a fresh Goal review from a fresh Quality review.
Architect, Browser QA, UI Critic, Test Engineer, Security Reviewer,
Diagnostician, and Sage remain conditional. Every repair and review gets a fresh
agent. A failed repair counts only when a completed correction still fails its
next applicable gate; stop after four materially similar failed repairs.
