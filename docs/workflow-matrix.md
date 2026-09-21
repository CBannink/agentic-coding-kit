# Workflow Matrix

## Execution modes

| Mode | Use when | Shape |
|---|---|---|
| `INLINE` | A minimal task whose implementation context, behavioral contract, and direct proof are already present before routing | Inspect → Change/Answer → Verify → Stop |
| `LOOP` | Discovery or implementation would consume substantial primary context, spans distinct responsibilities or contracts, or benefits from fresh judgment | Outcome/acceptance/authority/verification → builder-owned inspect–implement–check–repair → freeze candidate + fresh Reviewer → triage + delta recheck → finish |

The active host session is the only orchestrator and the only router. Skills
load lazily through their native triggers (`/<skill>`, `$<skill>`, or the
installed command forwarders); the router loads only the skill each request
needs. LOOP nodes are conditional and form a compact execution map, not a
mandatory workflow engine. One production writer is the default; up to three
Coders are allowed only for fixed contracts and disjoint write sets. Children
never dispatch successors or get reactivated after completion.

## Skills

| Skill | Use when | Main output |
|---|---|---|
| `build` | Production repository change | coherent diff and fresh proof |
| `design` | Product, prototype, or UI decision | validated design or Build handoff |
| `grill` | Explicit request for an intensive decision interview | agreed contract and open decisions |
| `review` | Independent judgment | material findings or pass |
| `pr-ready` | Human PR preparation | repaired, verified PR packet |
| `threat-model` | Material trust boundary | attack paths, controls, residual risk |
| `wiki` | Explicit repository knowledge init/reinit/audit | source-backed repository index |
| `async` | Cancellation, retries, concurrent state, or shared lifecycle | invariant, owner, tested interleaving, and gaps |
| `backend` | Backend boundary, persistence, or API contract | compatible change with failure evidence |
| `components` | Missing or uncertain UI primitive | verified existing component and usage evidence |
| `debug` | Unexplained failure or stalled repair | supported cause or ruled-out hypothesis |
| `deslop` | Requested cleanup or concrete complexity finding | smaller diff with preserved safeguards |
| `frontend` | Intentional UI design or review | decisions, reused assets, and rendered evidence |
| `migrate` | Schema, persisted-data, or rollout-order change | compatibility, rehearsal, and recovery limits |
| `perf` | Specified latency, throughput, or resource bottleneck | measured before/after results |
| `python` | Python behavior, resources, or type boundaries | verified change with runtime evidence |
| `security` | Named trust boundary or authorization rule | bounded finding with source evidence |
| `test` | Changed behavior needing durable proof | behavior-level regression evidence |
| `typescript` | TypeScript contracts, narrowing, or async boundaries | checked change with type evidence |

## Default LOOP realization

```text
Define outcome, acceptance, authority, and verification
→ builder-owned inspect–implement–check–repair loop
→ freeze the stable live diff as the candidate
→ fresh independent Reviewer (PASS/BLOCKED per criterion)
→ triage findings, repair accepted blocks, delta-recheck the new candidate
→ finish only when checks and review cover the final candidate
```

For consequential work, split a fresh Goal review from a fresh Quality review.
Architect, Browser QA, UI Critic, Test Engineer, Security Reviewer,
Diagnostician, and Sage remain conditional. Every repair and review gets a fresh
agent. A failed repair counts only when a completed correction still fails its
next applicable gate; stop after two unsuccessful repairs for the same material
failure.
