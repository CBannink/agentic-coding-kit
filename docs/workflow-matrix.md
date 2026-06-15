# Workflow Matrix

## When to use which workflow

| Workflow | Use when | Main output |
|---|---|---|
| `/goal` | you want autonomous goal achievement with iteration | goal verdict + handoff |
| `/plan` | you need an approval-ready implementation plan before coding | `plan.md` + `run-packet.json` |
| `/build` | you want code changed, tested, and reviewed | diff + verification evidence + reviewer outcome |
| `/review` | you want quality audit / code review | findings with false-positive-checked evidence |
| `/test-gen` | the expected test set is clear but coverage is missing | tests + build-verified iteration output |
| `/analyze` | you want research or architectural judgment | synthesis + optional build brief |
| `/investigate` | cause is unknown and must be proven | root-cause evidence + optional build brief |
| `/refactor` | you want structural improvement without behavior change | implementation + behavior-equivalence review |

## Default Engineering Loop

Normal code workflows use the same lean loop:

1. Load minimal indexed context only when needed.
2. Define the expected test set.
3. Implement with the needed tests.
4. Run fresh verification.
5. Spawn one `code-quality-reviewer`.
6. Spawn `security-reviewer` only for trust-boundary risk.
7. Repair BLOCKING findings and repeat, max 3 repair cycles.

Trust-boundary risk means auth/authz, secrets, crypto, permissions, untrusted
input, external HTTP, DB writes, filesystem paths, command execution, payments,
or sensitive data exposure.

The orchestrator owns test strategy and fresh verification evidence directly.
For behavior changes, the expected test set should include relevant
unit/integration coverage and E2E for user-visible flows when the repo can run
it. Use mock data or fixtures for external systems and edge cases. If E2E is
infeasible, record why and use the nearest integration, contract, or workflow
test. Legacy reviewer and verifier agents remain installed for compatibility
or explicit manual use, not normal routing.

## Scope And Tier

| Scope | Meaning |
|---|---|
| `ISOLATED` | local change, low blast radius |
| `SHARED` | shared interfaces, multiple modules, some integration risk |
| `CRITICAL` | auth, schema, public API, dangerous contracts, broad blast radius |

| Tier | Meaning |
|---|---|
| `INLINE` | direct answer or obvious mechanical edit |
| `TARGETED` | implementer + unified reviewer, plus explorer if unfamiliar |
| `FULL` | same loop with broader context and conditional security review |

## Goal Flow

`/goal` owns success criteria, scope, expected test set, E2E feasibility,
verification command, loop state, and blockers. It routes into the right
workflow and stops when criteria are met, the meaningful test set exists where
feasible, verification is green, and no BLOCKING unified-review finding remains.

Caps:

- max 3 repair cycles for the same blocker/task
- soft cap 6 total iterations
- hard cap 12 total iterations
