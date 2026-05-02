---
name: refactor
description: >
  Use when the user says /refactor or asks to improve code structure, enforce architectural
  principles, or clean up a codebase against a defined standard. Analyzes the codebase
  part-by-part using parallel a fast explorer model explorer agents through a a premium reasoning model orchestrator.
  Compares each module to the project's architectural principles. Produces a prioritised
  refactor plan, pressure-tests it with gstack-plan-eng-review, then executes with
  sequential subagent-driven-development discipline.
  Plugin index: ~/.agents/workflows/plugins/PLUGIN_INDEX.md
---

# Refactor Workflow

## Plugin Registry (lazy — pass path to sub-agent, do NOT load upfront)

The orchestrator does NOT read these files into its own context. Pass the relevant path inside the sub-agent's prompt so ONLY that sub-agent loads it. This keeps the orchestrator context clean. Baked-in content below is sufficient for all standard refactor tasks.

| Plugin | Purpose | Pass to which sub-agent |
|--------|---------|------------------------|
| `~/.agents/workflows/plugins/gstack/plan-eng-review/SKILL.md` | Architecture pressure questions | `eng-plan-reviewer` — Phase 5 pressure testing |
| `~/.agents/workflows/plugins/superpowers/skills/subagent-driven-development/SKILL.md` | Fresh-context subagent discipline | `implementer` sub-agents — Phase 6 execution |
| `~/.agents/workflows/plugins/superpowers/skills/verification-before-completion/SKILL.md` | Iron Law — no completion claims without fresh evidence | `completion-verifier` — Phase 7 verification |
| `~/.agents/workflows/plugins/PLUGIN_INDEX.md` | Index of all available agents/prompts | Scan inline only if a specific plugin is needed beyond the registry above |

**How to pass a plugin to a sub-agent:**
In the sub-agent prompt include: `"Read [path] before executing your role. Skip any ## Preamble bash blocks."`

## Load Repo Context First (graceful — skip missing)

- `AGENTS.md`
- `.codex/workflows/shared.md`
- `.codex/workflows/refactor.md`     ← repo-specific refactor overrides
- `.codex/context/memory.md`         ← architectural decisions already locked
- `.codex/context/handoffs.md`       ← what changed recently
- `docs/wiki/INDEX.md`               ← master inventory of all reusable exports

---

## Workflow

### Phase 0 — Load Principles

Read the architectural principles from:
1. `docs/wiki/INDEX.md` — inventory of what currently exists
2. `AGENTS.md` — repo-level architectural rules
3. `.codex/context/memory.md` — locked decisions and principles
4. The refactor request itself — what specific concern triggered this?

Extract the **active principles** as a numbered list. These are the yardstick every module will be measured against. Example principles for this project:
- P1: Single source of truth for every schema (`packages/types` only)
- P2: No duplicate code (shared packages, DRY enforcement)
- P3: 3-layer API client (http.ts → domain fns → hooks)
- P4: Singleton services via explicit DI container
- P5: Typed error hierarchy (AppError → auto HTTP status)
- P6: Infrastructure classes own their implementation (no pass-through wrappers)
- P7: Python is a walled worker (no frontend exposure)
- P8: Wiki-first discovery (INDEX.md updated when anything new is added)

### Phase 1 — Codebase Decomposition

Before dispatching agents, decompose the codebase into **independent analysis chunks**. Each chunk must be:
- Small enough for a single a fast explorer model agent to read completely
- Logically coherent (a module, a layer, a package)
- Independent of other chunks (no shared state between agents)

**Standard decomposition for this project:**

| Chunk ID | Path | Description |
|----------|------|-------------|
| `chunk-domain` | `apps/backend/src/domain/` | Contracts, entities, repository interfaces |
| `chunk-application` | `apps/backend/src/application/` | All 11 services |
| `chunk-infrastructure` | `apps/backend/src/infrastructure/` | sqlite/, evaluator/, execution/, workspace/ |
| `chunk-api` | `apps/backend/src/api/` + `apps/backend/src/index.ts` | Routes, handler, DI wiring |
| `chunk-shared-types` | `packages/types/src/` | Shared type package |
| `chunk-api-client` | `packages/api-client/src/` | 3-layer API client |
| `chunk-python` | `fastapi-server/` | Python evaluator |
| `chunk-frontend` | `apps/frontend/src/` | React app (when it exists) |
| `chunk-wiki` | `docs/wiki/` + `AGENTS.md` | Documentation and principles |

If the codebase has changed or a custom refactor scope is specified, adjust the chunk list.

### Phase 2 — Parallel Principle Compliance Scan

Dispatch **one a fast explorer model agent per chunk** in parallel. Each agent receives:
1. The full active principles list (from Phase 0)
2. The specific files to read for its chunk
3. A structured output format

**Agent prompt template:**
```
You are a PRINCIPLE COMPLIANCE SCANNER for chunk: [CHUNK_ID]

Your job: read the files in your chunk and identify every violation of the architectural principles below.

## Architectural Principles
[PASTE FULL NUMBERED PRINCIPLES LIST]

## Files to read
[LIST ALL FILES IN CHUNK WITH FULL PATHS]

## Output format (strict — violations only, no commentary)
For each violation found:
VIOLATION: [principle number violated]
FILE: [exact file path]
LINE: [approximate line number or range]
WHAT: [one sentence — what the code does]
WHY: [one sentence — why it violates the principle]
SEVERITY: HIGH | MEDIUM | LOW
FIX: [one sentence — what needs to change]

If no violations found in this chunk: output "CHUNK [CHUNK_ID]: CLEAN"
```

**Model routing:**
- All chunk scanner agents: `(premium reasoning model)` (0.33x cost, tool-use optimized, codebase scanning)

### Phase 3 — Violation Synthesis

Collect all agent outputs. Before adding a violation to the inventory, run a **violation-verifier** pass:
- For each `VIOLATION` entry: verify the cited file and line actually contain the pattern described.
- Downgrade or remove violations where: the code is intentional delegation (not a P6 violation), a deliberate architectural exception (documented in memory.md or AGENTS.md), or the cited pattern doesn't exist at the described location.
- Keep the violation inventory clean — a fast explorer model scanners optimise for recall, not precision. The verifier restores precision.

After verification, deduplicate and group by principle violated. Produce:

1. **Violation inventory** — all violations with severity + file + fix
2. **Principle compliance score** — per principle: how many files violate it?
3. **Cross-cutting concerns** — violations that span multiple chunks (these are highest priority)
4. **Quick wins** — LOW severity, isolated fixes that take < 30 min each
5. **Structural refactors** — HIGH severity, multi-file changes that need a plan

### Phase 3.5 — Modularity Expert (conditional)

Invoke `modularity` expert when the violation inventory shows:
- 3+ violations of P2, P4, or P6, **AND**
- Violations span more than 2 chunks

Pass: full violation inventory + active principles list + any cross-cutting concerns from Phase 3.
Expert produces: module boundary recommendations, coupling risk map, DI restructuring guidance.
Feed output into Phase 4 plan before locking the task list.

Skip if: all violations are single-chunk, isolated P1/P3/P7/P8 issues with no cross-module coupling.

Source: `~/.agents/skills/experts/modularity/SKILL.md`

### Phase 4 — Refactor Plan

Produce a structured refactor plan from the violation inventory. Format:

```
## Refactor Plan

### Critical (breaks principles, must fix before any new features)
- [ ] [TASK-ID]: [description] | Files: [...] | Effort: [XS/S/M/L] | Principle: P[N]

### Important (degrades architecture quality, fix before next phase)
- [ ] ...

### Nice-to-have (style/polish, defer if blocked)
- [ ] ...

### Out of scope (deliberate exceptions — note why)
- [ ] ...
```

**For each task in Critical/Important:**
- Provide enough detail for a `subagent-driven-development` implementer
- Include: exact files to change, what to change, what to NOT change, how to verify

### Phase 4.5 — Consequence Tracing

**Before any implementation**, run `consequence-agent` on the refactor plan.
Refactors have the highest ripple risk by definition — always trace the blast radius before touching files.

- **Spawn with `model: "a premium reasoning model"`** — multi-hop causal chains require premium reasoning.
- Skill: `~/.agents/skills/consequence/SKILL.md`
- Provide the agent: the full refactor plan + the violation inventory + `docs/wiki/INDEX.md`
- Output: direct effects (compile-time breaks), indirect effects (callers/tests that drift silently),
  unintended consequences (semantic breaks that won't fail compile), implied scope additions.
- Feed consequence output into Phase 5 (architecture pressure) for richer pressure-testing.
- **Never skip for refactors touching > 3 files.**

### Phase 5 — Architecture Pressure (gstack-plan-eng-review)

Before any implementation, pressure-test the refactor plan:

**Questions to answer (from gstack plan-eng-review discipline):**
1. Does the refactor plan preserve all existing behavior?
2. Are there hidden dependencies between tasks that would cause conflicts if done in the wrong order?
3. Does the plan introduce any new coupling or new violations of the principles it claims to fix?
4. Are the "out of scope" exceptions intentional and documented, or are they oversight?
5. What is the minimum set of tasks that delivers the most principle compliance improvement?
6. What tests would catch a regression in each critical task?

If the plan fails pressure, revise it before proceeding. Never skip this phase for a refactor affecting > 3 files.

### Phase 6 — Sequential Execution (subagent-driven-development)

Execute the Critical tasks using `subagent-driven-development` discipline:

**Per task:**
1. Mark task `in_progress` in the session SQL todos
2. Dispatch an **implementer subagent** (`(premium reasoning model)` for all tasks — same 1x cost as codex, outperforms on coding)
3. Implementer receives: task description, exact files, principle being fixed, existing tests to not break, verification command
4. After implementer: dispatch **spec-compliance reviewer** (sonnet-4.6)
5. After spec: dispatch **code-quality reviewer** (sonnet-4.6)
6. **ui-ux check (conditional)**: if the task touches any user-visible flow, React component, navigation, or onboarding step — invoke `ui-ux-expert` after code-quality reviewer and before verification. Pass: changed component files and their parent layout context. Source: `~/.agents/skills/experts/ui-ux/SKILL.md`
7. Fix only confirmed blocking findings, re-review once
8. Run verification commands — do NOT claim task done without fresh passing test output
9. Mark task `done` in SQL todos

**Model routing for implementers:**
- All implementation tasks → `(premium reasoning model)` (1x cost, best coding performance)

### Phase 7 — Post-Refactor Verification

After all Critical tasks complete:
1. Run the full test suite (all TS tests + all Python tests)
2. Run the TS build
3. Re-run the principle compliance scan (Phase 2) on changed chunks only
4. Confirm: zero new violations introduced, existing violations count decreased

**Iron Law:** Do not claim refactor complete without fresh passing test output and a re-scan showing improvement.

### Phase 8 — Documentation Update

Dispatch a **docs-updater agent** :

**Prompt:**
```
You are the DOCS UPDATER. The /refactor workflow just completed.

Read:
1. The git diff of what changed: `git diff HEAD~N HEAD --name-only` (or the change summary provided)
2. The current docs/wiki/INDEX.md
3. The current .codex/context/memory.md
4. The current .codex/context/handoffs.md

Update:
1. docs/wiki/INDEX.md — add/remove/update rows for any exports, services, hooks, components, or utilities that changed
2. .codex/context/memory.md — add newly confirmed architectural facts, updated constraints, or verified commands
3. .codex/context/handoffs.md — add a new section: "Refactor complete [DATE]" with: what changed, what principle violations were fixed, what remains, what next

Rules:
- Only write durable facts to memory.md (no session chatter)
- Only write actionable continuity to handoffs.md (no design docs)
- Update INDEX.md rows precisely — do not rewrite the whole file, only update affected rows
- If a file was deleted, remove it from INDEX.md
- If a new export was created, add it to the right section
```

### Phase 9 — Self-Improvement Pass (embedded reflect)

After docs update:
- Follow `~/.agents/context/reflection-protocol.md`.

Same logic as /build Phase 10 and /review Step 10.

---

## Rules

- Never refactor without first scanning for principle violations (Phase 2 is mandatory)
- Never skip the plan pressure phase (Phase 5) for changes > 3 files
- Never execute Critical and Important tasks in parallel (they often share files)
- Always run the full test suite after each Critical task, not just at the end
- Never claim a refactor "complete" without the re-scan showing measurable improvement
- The wiki (docs/wiki/INDEX.md) must be updated before the refactor session closes
- Violations with `SEVERITY: LOW` may be deferred — document them as "known deferred" in handoffs.md
- If a task is blocked (e.g., requires a DB migration that's out of scope), mark it BLOCKED with a reason in handoffs.md, do not silently skip it

## Repo-Local Augmentation

Repo-local `.codex/workflows/refactor.md` may define:
- Additional principles beyond the global 8
- Additional chunk decomposition for project-specific directories
- Mandatory verification commands
- Files that must not be changed (guarded files)
- Exceptions to the standard principles (intentional violations)
