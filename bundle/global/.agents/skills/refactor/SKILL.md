---
name: refactor
description: Use when the user asks to refactor, restructure, clean up, consolidate, or apply DRY/SOLID. Runs principle lock, consequence trace, implement with behavior equivalence, review, verify.
---

# /refactor

Behavior MUST be identical after refactoring. Only structure changes. No feature additions.

## Phase 1 — Principle lock

State the refactoring principle explicitly. Without a named principle, refactors drift into rewrites. Valid principles:
- **Reuse-first**: extract shared logic, eliminate duplication
- **Boundary cleanup**: separate concerns, fix layer violations
- **Type safety**: add types, remove `any`, tighten contracts
- **DI rewiring**: decouple dependencies, invert control
- **Layered architecture**: enforce module boundaries

Output: `PRINCIPLE: <name> | target: <files/directories>`

## Phase 2 — Consequence trace

Spawn `workflow-explorer` to map: all call sites of the target code, test files that cover it, public exports/APIs/types that must NOT change. Read the synthesis.

Also check `.wiki/features.md` for any user-visible behavior that depends on the target surface. If the refactor changes a public API or export, the wiki must be updated.

## Phase 3 — Prompt synthesis (before implementer)

Spawn `prompt-synthesizer` with: the refactor principle, call-site map, target type "implementer", and the constraint "Behavior must be identical — run tests before and after." Use its `PROMPT_SYNTHESIS` output.

## Phase 4 — Implementation

Spawn `workflow-implementer` with the synthesized prompt from Phase 3. Do NOT implement inline — always delegate.

Mark gate: `pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "implementation_done"`

## Phase 5 — Behavior-equivalence review

Spawn `code-quality-reviewer` with explicit REFACTOR prompt: "Verify behavior unchanged. Original test cases still asserting? Public APIs untouched? Every error path preserved? Accidental simplifications that change semantics?"

If behavior drift is found: re-spawn implementer with the drift as deltas. Cap at 2 iterations.

## Phase 6 — Modularity verification

Spawn `modularity-expert` to confirm the principle from Phase 1 was achieved. If the refactor claimed to extract shared logic but left duplicates, or claimed to fix layering but created new violations, surface this.

## Phase 7 — Verification

Run verification command inline. Capture exit code. Spawn `final-verifier`. Run writeback: `pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "<id>"`. Mark gates.

## Phase 8 — Handoff

Summarize: principle, files changed, behavior preserved (verification exit code), any modularity findings.
