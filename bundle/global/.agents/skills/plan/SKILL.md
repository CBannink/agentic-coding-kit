---
name: plan
description: >
  Plan-first workflow for targeted coding tasks. Clarifies scope, maps likely files,
  explores repo and wiki context, pressure-tests the approach, writes a session plan
  artifact, and waits for approval before any implementation begins. Lightweight
  compared to /spec; intended to chain directly into /build.
---

# Plan Workflow

Use `/plan` when you want the Claude Code-style planning experience before any code changes:
- clarify real ambiguities
- inspect the relevant repo context
- identify the likely files to change
- lay out the implementation approach and verification strategy
- stop for approval before coding

Use `/plan` for targeted coding tasks that need a strong execution plan but do **not** need a durable repo spec.
Use `/spec` instead when the change needs a formal cross-session requirements document in `.codex/specs/`.

---

## Load Context First (graceful — skip missing files)

When these files exist in the current repo, read them before planning:
- `~/.agents/skills/plan/memory.md`
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `.codex/workflows/shared.md`
- `.codex/workflows/build.md`
- `.codex/context/memory.md`
- `.codex/context/history.md`
- `.codex/context/handoffs.md`
- `.wiki/index.md` *(read FIRST when the wiki exists -- canonical TOC, ≤100 lines, lists all sections + cross-cutting links. Cheaper than guessing what's in the wiki.)*
- `.wiki/features.md` *(only when user-visible behavior or feature discovery is relevant)*
- `.wiki/.features` *(only when `.wiki/features.md` is relevant and a machine-readable manifest helps)*

**On-demand section loading**: do NOT bulk-read `.wiki/sections/`. Use the
lazy-load resolver to fetch only relevant sections:
```powershell
pwsh ~/.agents/tools/wiki-resolver.ps1 -Task "{task}" -ChangedFiles "{files}" -RepoRoot .
```
The resolver returns `index.md` + matched sections in one prompt block.
Embed only what it returns -- never hand-pick section files yourself.

If `.wiki/` is missing entirely, prompt the user to run `/wiki-init`
before non-trivial planning (per the kit's always-on rules).

Treat repo-local files as overrides.

Repo-local specialist memory is **lazy-loaded**, not startup-loaded:
- `.codex/context/agent-memory/shared.md`
- `.codex/context/agent-memory/{role}.md`

Before spawning any planning-role sub-agent that might benefit from repo-local specialist context, resolve it mechanically with:

`pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId "{session_id}" -Role "{role}" -RepoRoot "{repo-root}"`

If the resolver returns `found=true`, embed its `prompt_block` directly in the sub-agent prompt.

---

## Planning Artifact

Write or update the session plan artifact at:

`~/.agents/session-state/{session_id}/plan.md`

This is the authoritative output of `/plan` and the preferred input contract for `/build`.

If no harness `SESSION_ID` exists, use the active CLI session folder's `plan.md`.

Also maintain the compact session contract at:

`~/.agents/session-state/{session_id}/run-packet.json`

Use `pwsh ~/.agents/tools/run-packet.ps1` to keep the approved plan summary, likely files, integration points, and verification expectations compact enough for `/build`, hook helpers, and specialists to reuse without reloading the full planning transcript.

---

## Workflow Tier

| Tier | Pick when | Policy |
|------|-----------|--------|
| **INLINE** | Small, clear request; likely ≤3 files; no meaningful tradeoffs | Minimal questions, compact plan, still write plan artifact |
| **TARGETED** | 2–6 likely files, some ambiguity, some integration risk | Read repo context, ask focused clarifications, produce file-level plan |
| **FULL** | Design unclear, shared contracts, schema/auth/public API, or meaningful blast radius | Add consequence and architecture pressure before finalizing plan |

**Default when unsure: TARGETED, not FULL.**

---

## Default Agent Matrix

### Explore
- `wiki-explorer`
  Purpose: inspect `.wiki/features.md` and `.wiki/.features` when user-visible capability mapping matters.
- `architecture-explorer`
  Purpose: map likely owners, boundaries, and dependency flow for the requested change.
- `integration-explorer`
  Purpose: find registration points, callers, downstream dependencies, and reusable test helpers.
- `history-explorer`
  Purpose: inspect recent history, fragile areas, and reverted fixes in the touched surface.
- `ownership-explorer`
  Purpose: verify that each planned file directly owns the required behavior rather than being a nearby false owner.

### Pressure / Verify
- `consequence-agent`
  Purpose: trace blast radius and implied scope before implementation.
- `eng-plan-reviewer`
  Purpose: devil’s-advocate pressure on the plan: simpler paths, failure modes, missing tests, weak ownership.

**Planning principle:** `/plan` should do the expensive exploration and criticism so `/build` can stay execution-heavy.

---

## Required Plan Sections

Every `/plan` result must include:

1. **Goal** — what outcome is being delivered
2. **Clarifications / Assumptions** — resolved ambiguities or explicit assumptions
3. **Files Likely to Change** — exact paths or best-known likely paths, plus why each file is involved
4. **Approach** — ordered implementation path
5. **Risks / Blast Radius** — what could break or drift
6. **Verification Strategy** — tests/build/checks that should prove completion
7. **Parallelization** — what is serial, what is parallel-safe, what is parallel-safe after prerequisites
8. **Out of Scope** — explicit exclusions
9. **Approval Status** — pending / approved / superseded

Use this structure in `plan.md`:

```markdown
# Build Plan: [task]
*Created: YYYY-MM-DD | Status: pending-approval*

## Goal
[1-2 sentences]

## Clarifications / Assumptions
- [...]

## Files Likely to Change
| File | Why it is involved |
|------|--------------------|
| `src/...` | [reason] |

## Approach
1. ...
2. ...

## Risks / Blast Radius
- [...]

## Verification Strategy
- [...]

## Parallelization
### Serial
- [...]

### Parallel-safe
- [...]

### Parallel-safe after prerequisite
- [...]

## Out of Scope
- [...]

## Approval
Status: pending-approval
Notes: awaiting user confirmation
```

---

## Clarification Rules

- Ask only the minimum questions needed to remove real ambiguity.
- Prefer one question at a time.
- If the user already implied a reasonable default, state it as an assumption instead of asking.
- If the user says "just figure it out", proceed with assumptions and label them clearly.

---

## Planning Pressure

For **FULL** plans, or any plan with meaningful integration risk:
- pressure-test the approach using `gstack-plan-eng-review`
- trace direct blast radius when shared contracts are involved

Questions to answer before finalizing:
1. Are we changing the right owner files?
2. What would break if the plan is wrong?
3. Is there a simpler path?
4. What verification would disprove a bad implementation quickly?

---

## Workflow

1. Load repo-local context files when they exist.
2. Decide planning tier.
3. Run explorers only for gaps that matter to the plan:
   - prefer `wiki-explorer` first for user-visible or feature-oriented work
   - then add `architecture-explorer`, `integration-explorer`, `history-explorer`, or `ownership-explorer` only as needed
   - keep exploration broad in `/plan`, not `/build`
4. Synthesize the evidence into:
   - likely files touched
   - ownership rationale
   - integration points
   - verification expectations
   - serial vs parallel-safe work
5. Run `consequence-agent` when the plan touches shared contracts, public API surfaces, schemas, DI/container wiring, or multi-module boundaries.
6. Run `eng-plan-reviewer` for **FULL** plans and any plan with meaningful architecture or integration risk.
7. Write or refresh `plan.md` and `run-packet.json`.
8. Present the plan and stop for approval.

**Rule:** if `/plan` already ran the heavy exploration and pressure passes, `/build` should not repeat them unless plan freshness fails.

---

## Integration with `/build`

When `/build` sees an approved same-session `plan.md`, it should:
1. use that artifact as the primary execution contract
2. use `run-packet.json` as the compact execution packet
3. avoid regenerating the plan unless the task changed materially
4. pass the approved plan to `implementer` and `spec-reviewer`
5. enforce plan-to-diff fidelity against that artifact

If no approved plan exists, `/build` should perform this planning workflow first and stop for approval.

---

## Output Contract

Before stopping, present:

```text
PROPOSED BUILD PLAN
===================
[summary]

Files likely to change:
1. ...
2. ...

Risks:
- ...

Verification:
- ...

Parallelization:
- Serial: ...
- Parallel-safe: ...

→ Approve this plan, or correct it before /build proceeds.
```

Never implement during `/plan`.
