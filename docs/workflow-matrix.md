# Workflow Matrix

## When to use which workflow

| Workflow | Use when | Main output |
|---|---|---|
| `/plan` | you need an approval-ready implementation plan before coding | `plan.md` + `run-packet.json` |
| `/build` | you want code changed, built, reviewed, and verified | diff + verification evidence |
| `/review` | you want quality audit / code review | findings with verifier-filtered evidence |
| `/analyze` | you want research or architectural judgment | synthesis + optional build brief |
| `/investigate` | cause is unknown and must be proven | root-cause evidence + optional build brief |
| `/refactor` | you want structural improvement against principles | refactor plan + implementation |

## Autonomous flow selection

The system makes **two decisions**:

### 1. Scope

| Scope | Meaning |
|---|---|
| `ISOLATED` | local change, low blast radius |
| `SHARED` | shared interfaces, multiple modules, some integration risk |
| `CRITICAL` | auth, schema, public API, dangerous contracts, broad blast radius |

### 2. Tier

| Tier | Meaning |
|---|---|
| `INLINE` | lite flow |
| `TARGETED` | medium flow |
| `FULL` | critical/full swarm flow |

This is how the system achieves **lite / targeted / critical** behavior without user micromanagement.

## Agent shapes by workflow

### `/plan`

Typical roles:
- `wiki-explorer`
- `architecture-explorer`
- `integration-explorer`
- `history-explorer`
- `ownership-explorer`
- `consequence-agent`
- `eng-plan-reviewer`

### `/build`

Typical roles:
- `plan-freshness-checker`
- `delta-explorer`
- `patterns-explorer`
- `implementer`
- `spec-reviewer`
- `code-quality-reviewer`
- `modularity-expert`
- `security-reviewer`
- `build-loop-gate`
- `adversarial-reviewer`
- `final-verifier`

### `/review`

Hierarchical swarm:

#### Surface reviewers
- `software-reviewer`
- `security-reviewer`
- `api-reviewer`
- `testing-reviewer`
- optional surface specialists (`performance-reviewer`, `maintainability-reviewer`, `data-migration-reviewer`)

#### Interaction reviewers
- `caller-callee-reviewer`
- `shared-contract-reviewer`
- `state-flow-reviewer`

#### Parent merge layer
- `synthesis-reviewer`

#### Final passes
- `adversarial-reviewer`
- `false-positive-verifier`

### `/analyze`

Typical roles:
- `architecture-explorer`
- `surface-explorer`
- `impact-explorer`
- `pragmatist`
- `skeptic`
- `claim-verifier`
- optional `consequence-agent`

### `/investigate`

Typical roles depend on the failure, but the logic is hypothesis-driven rather than role-first.

## Why this matters

The system does **not** treat every change as a swarm problem.

It uses:
- **lite** when direct reads are enough
- **targeted** when there are some real boundaries or unknowns
- **full** when contracts, auth, migrations, or system interactions are risky
