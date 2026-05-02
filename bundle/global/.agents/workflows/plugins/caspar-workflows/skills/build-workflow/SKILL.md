---
name: build-workflow
description: Use when the user says /build or asks to build, implement, fix, refactor, or change code with a full multi-agent loop. Supports repo-local augmentation from AGENTS.md, CLAUDE.md, GEMINI.md, and .codex/workflows/build.md.
---

# Build Workflow

## Load Context First

Before planning or coding, read these files when they exist:
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `.codex/workflows/shared.md`
- `.codex/workflows/build.md`
- `.codex/context/memory.md`
- `.codex/context/handoffs.md`

Treat those files as repo-local overrides on top of this workflow.

## Default Agent Matrix

Use this roster unless repo-local build instructions replace or extend parts of it.

### Phase 0: Explore

- `architecture-explorer`
  Purpose: map relevant modules, entry points, dependency flow, and ownership boundaries.
  Source bias: custom workflow base + Superpowers exploration discipline.
- `patterns-explorer`
  Purpose: find 2-3 existing implementations to copy for code shape, tests, and naming.
  Source bias: Superpowers pattern matching.
- `integration-explorer`
  Purpose: identify registration points, constraints, downstream callers, and reusable test helpers.
  Source bias: Superpowers integration tracing.
- `history-explorer`
  Purpose: inspect recent commits, TODOs, and fragile areas when touching existing code.
  Source bias: Superpowers prior-art and history review.

### Phase 1: Plan

- `eng-plan-reviewer`
  Purpose: challenge architecture, data flow, failure modes, and test gaps before code.
  Source bias: gstack `plan-eng-review`.

### Phase 2-6: Build Loop

- `implementer`
  Purpose: implement only the scoped task with minimal diff and fresh context.
  Source bias: Superpowers `subagent-driven-development`.
- `spec-reviewer`
  Purpose: verify the implementation matches the agreed plan and did not add scope.
  Source bias: Superpowers spec-compliance review.
- `code-quality-reviewer`
  Purpose: check maintainability, correctness, conventions, and test quality.
  Source bias: Superpowers code review + gstack reviewer sharpness.
- `security-reviewer`
  Purpose: review trust boundaries, injection risks, auth mistakes, data leaks, and failure handling.
  Source bias: gstack `review` specialists.
- `verification-gate`
  Purpose: decide pass/fail based on actual test output and confirmed findings.
  Source bias: your workflow + Superpowers `verification-before-completion`.

### Phase 7: Final Validation

- `qa-reviewer`
  Purpose: browser or user-flow validation for UI/web changes, plus issue triage.
  Source bias: gstack `qa`.
- `adversarial-reviewer`
  Purpose: attack the diff for production failure modes, regressions, and hidden risks.
  Source bias: gstack `review` adversarial posture.
- `completion-verifier`
  Purpose: enforce no-success-claims-without-fresh-evidence.
  Source bias: Superpowers `verification-before-completion`.

## Prompt Catalog

Default role prompts live under:
- `plugins/caspar-workflows/prompts/build/`

Repo-local build instructions may:
- append additional constraints to a default role
- disable a default role
- add extra domain-specific roles
- replace a role entirely when the domain requires it

## Routing Rule

Use this workflow when the user explicitly says `/build` or when the request is non-trivial implementation work. Trivial one-line changes can be done directly, but still respect tests and verification.

## Workflow

1. Explore with parallel agents. Gather facts only.
2. Synthesize what to follow: relevant files, patterns, integration points, test strategy, and constraints.
3. Run `eng-plan-reviewer` before non-trivial implementation when architecture or integration risk is present.
4. Present a concise plan before major implementation.
5. Run the implementation loop with a maximum of 5 iterations:
   - `implementer` builds only the scoped change
   - run relevant tests and lint/build checks
   - `spec-reviewer` checks compliance against the agreed scope
   - `code-quality-reviewer` and `security-reviewer` run in parallel
   - `verification-gate` confirms which findings are real and blocking
   - fix only confirmed blocking issues, then loop
6. Final validation:
   - run `qa-reviewer` for UI or behavior-heavy changes
   - run `adversarial-reviewer` for final failure-mode review
   - `completion-verifier` enforces fresh evidence before completion
7. Completion gate:
   - do not claim completion without fresh test output
   - update affected docs or config only when the change requires it
8. **Post-build documentation update (always, every /build):**
   - Dispatch a `docs-updater` agent (`claude-haiku-4.5`) after every successful build
   - Agent reads: git diff summary, current `docs/wiki/INDEX.md`, current `memory.md`, current `handoffs.md`
   - Agent updates:
     - `docs/wiki/INDEX.md` — add/update/remove rows for any exports, hooks, services, or utilities that changed
     - `.codex/context/memory.md` — promote newly confirmed facts, constraints, or verified commands
     - `.codex/context/handoffs.md` — append current status, what was built, what tests passed, next steps
   - Agent prompt key rules: only durable facts to memory.md, no session chatter; only actionable continuity to handoffs.md; update INDEX.md rows precisely, do not rewrite the whole file
   - If the build **failed**, the docs-updater still runs but only updates handoffs.md with what was attempted and what blocked it

## Build Loop Rules

- Always explore before coding.
- For non-trivial features, design and plan before implementation.
- Always verify before claiming done.
- Cite file references when summarizing findings.
- Stop and ask the user after 3 failed root-cause attempts or 5 full build-loop failures.
- Do not add features beyond scope.
- Prefer existing project dependencies and conventions over introducing new ones.
- Prefer Superpowers for execution control and gstack for adversarial review, QA, and production-risk framing.
- `handoffs.md` is operational memory, not a design doc.
- `memory.md` is durable repo memory; avoid session-specific noise.
- `reflections.md` is for suggested workflow or prompt improvements, not silent live self-rewrites.

## Repo-Local Augmentation Contract

Repo-local build instructions may define:
- Required test, lint, or build commands
- Additional specialist agents
- Role replacements for domain-specific implementations
- Domain-specific constraints
- Extra completion gates
- Preferred order for reviewer or verifier roles
- Additional memory or handoff update rules

If repo-local instructions conflict with this skill, follow the repo-local instructions.
