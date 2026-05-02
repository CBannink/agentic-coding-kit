---
name: consequence
description: >
  Forward causal tracer. Given a plan, diff, or proposed change — traces ripple effects
  through the codebase dependency graph BEFORE implementation. Surfaces direct effects,
  indirect effects, unintended consequences, and implied scope additions.
  Invoke with /consequence or automatically triggered inside /build and /review when
  a change touches shared interfaces, public API surfaces, or cross-module contracts.
---

# Consequence — Forward Causal Tracing

## What this skill does

A consequence agent is not a quality judge. It does not say "this is bad architecture."
It does not find bugs in existing code.

It answers one question:

> **"If this plan or change executes, what else in the codebase changes — including
> things the plan didn't mention?"**

It is a **forward causal tracer**: given a proposed change, it walks the dependency
graph and reports the full blast radius — direct, indirect, and silent — before a
single line is implemented.

---

## Load Context First (graceful — skip missing)

Read these when they exist:
```
.codex/context/memory.md       — durable repo facts, confirmed dependency patterns
.codex/context/handoffs.md     — current state, open work, known fragile areas
docs/wiki/INDEX.md             — all public exports, services, endpoints (blast-radius map)
```

---

## Agent Matrix

### Explore phase (always, parallel)

- `import-graph-explorer`
  Purpose: map the import dependency tree for the files the plan touches. Who imports what?
  Find all consumers of changed modules, types, and interfaces.
  Model: `(premium reasoning model)` — I/O-bound read task; GitHub-recommended for agentic exploration.

- `contract-surface-explorer`
  Purpose: identify all public contracts the plan touches — Zod schemas, TypeScript interfaces,
  Pydantic models, API routes, database schema, CLI flags. What is the exposed surface?
  Model: `(premium reasoning model)`

- `test-fixture-explorer`
  Purpose: find all test files that reference the changed modules, types, or routes.
  Which tests will need updating? Which test fixtures make assumptions about the current shape?
  Model: `(premium reasoning model)`

### Consequence synthesis (always, after explore)

- `consequence-synthesizer`
  Purpose: take the explore results and the proposed plan. Build a causal chain:
  "A changes → B must adapt → C may break silently."
  Distinguish between compile-time breaks (will surface immediately) and semantic breaks
  (compile but behave wrong — the dangerous ones).
  Model: `(premium reasoning model)` — multi-hop causal reasoning requires premium model.

---

## Workflow

1. **Receive the plan or diff** — natural language description, a formal plan, or a code diff.

2. **Load context** — read `memory.md`, `handoffs.md`, `docs/wiki/INDEX.md` when they exist.
   Extract: known fragile areas, guarded files, confirmed dependency patterns.

3. **Run parallel explorers** — import graph, contract surface, test fixtures.
   Goal: build a dependency map centered on the proposed change.

4. **Synthesize consequences** — run `consequence-synthesizer` with plan + explore results.

5. **Report structured output** (see Output Format below).

6. **Do not implement** — this skill never modifies files. It is purely analytical.
   Hand results back to the caller (/build, /review, or the user directly).

---

## Output Format

Always structure output in four sections:

### 1. Direct Effects
*Files and modules that MUST change for the plan to compile or run.*
- List each file with a one-line reason.
- Distinguish: "needs update" vs "will break at compile time."

### 2. Indirect Effects
*Callers, consumers, tests, docs, and wiki entries that need updating.*
- These won't break immediately but will silently drift if not updated.
- Typical: test fixtures that assume the old shape, wiki rows for changed APIs,
  api-client functions that call a renamed route, DI container wiring for a moved service.

### 3. Unintended Consequences
*Semantic breaks that won't surface as compile errors or test failures — the dangerous ones.*

These are the highest-value output of this agent. Examples:
- "Field serializes under wrong key due to alias/model_config mismatch — Node drops it silently."
- "Component defined inside parent function body — React remounts it on every state change."
- "CLI argument parsed but value never threaded into the executing function — flag has no effect."
- "Empty criteria list passes validation — quality gate runs with no checks."

For each: state the mechanism ("because X, Y will happen") not just the symptom.

### 4. Implied Scope Additions
*Things the plan assumes but did not explicitly state.*

These often cause scope creep when discovered mid-build. Surface them upfront:
- "Plan says 'add route' but doesn't mention updating `container.ts` to register the new service."
- "Plan says 'rename field' but doesn't mention updating the Python Pydantic model that mirrors it."
- "Plan says 'add CLI flag' but doesn't mention threading it into the function that uses it."

---

## Trigger Conditions

Run consequence analysis when the plan or diff touches:

| Trigger | Why |
|---------|-----|
| `packages/types/src/index.ts` | All consumers in the monorepo depend on this — highest blast radius |
| Any Pydantic model in `fastapi-server/models.py` | Python/TS contract boundary — mismatches are silent |
| `container.ts` (DI wiring) | Every service consumer is affected; missing registration = runtime crash |
| `db.ts` (schema) | Migration implications; existing data may not match new shape |
| Public API routes (path or body shape) | All API clients and tests that call this route are affected |
| Shared React components or hooks | All parent components that render them; hook state implications |
| `packages/api-client/` public functions | All frontend hooks and pages that call them |
| CLI entry points | All scripts and CI steps that invoke the CLI |

**Skip for:**
- Single-file changes with no shared interface dependencies
- Style/CSS/Tailwind-only changes
- Documentation-only changes
- Test-only changes (unless they change test utilities used by other tests)

---

## Integration with Other Workflows

### In /build

Insert between explore phase and plan presentation:

```
explore agents → consequence-agent → gstack-plan-eng-review → implementer
```

The consequence agent gives `plan-eng-review` a richer input: the plan *plus its known
blast radius*. Architecture pressure is more useful when applied to concrete downstream effects,
not just the plan in isolation.

**Invoke when:** the plan touches any trigger condition listed above.

### In /review

Insert after specialist reviewers, before adversarial pass:

```
parallel specialists → consequence-agent → adversarial-reviewer → false-positive-verifier
```

In review context, the consequence agent specifically targets **what isn't in the diff** —
the callers, consumers, tests, and contracts that will silently break because the changed
interface no longer matches what they expect.

**Invoke when:** the diff modifies a public interface, shared type, or cross-module contract.

### In /analyze

Use in the synthesis phase when comparing design options:

```
explore multiple options → consequence-agent per option → synthesize comparison
```

The consequence agent projects the consequence *set* of each option. Enables evidence-based
comparison: "Option A has 3 downstream effects. Option B has 7, including a breaking change
to the Python/TS contract."

### In /refactor

Refactors have the highest ripple risk by definition. Run consequence analysis
**before the implementer touches any file**:

```
explore codebase → consequence-agent on the refactor plan → implementer
```

Map the blast radius of every move, rename, or restructure upfront.
Never start a refactor without knowing the full scope of what needs to change.

---

## Model Routing

- `consequence-synthesizer`: **`(premium reasoning model)`** — non-negotiable.
  Multi-hop causal chains ("A changes → B adapts → C breaks silently") require
  premium reasoning. Haiku and Sonnet miss the third-order effects. Do not downgrade.

- Explore agents: **`(premium reasoning model)`** — I/O-bound file reads, low latency, GitHub-recommended for agentic codebase exploration.

---

## What this agent must NOT do

- **Never implement** — reads only, no file modifications.
- **Never judge quality** — "this is bad architecture" is `plan-eng-review`'s job.
- **Never find bugs in existing code** — that is `adversarial-reviewer`'s job.
- **Never block on trivia** — don't report trivial rename effects as "unintended consequences."
  Signal-to-noise discipline: only report effects that a developer could miss.
- **Never self-modify** this skill file.

---

## Relation to Existing Agents

| Agent | Job | Consequence agent difference |
|-------|-----|------------------------------|
| `gstack-plan-eng-review` | Is the plan good? | Doesn't trace what the plan *breaks* |
| `adversarial-reviewer` | What fails in existing code? | Backward-looking, not forward |
| `spec-reviewer` | Does implementation match scope? | Can't catch missed scope before build |
| `explore agents` | Gather facts | Don't synthesize causal chains from facts |
| `false-positive-verifier` | Are findings real? | Doesn't generate new ripple-effect findings |

The consequence agent fills the gap between "we have a plan" and "we understand its full scope."
It gives the LLM the ability to reason about the **future state of the codebase** before
committing to implementation.
