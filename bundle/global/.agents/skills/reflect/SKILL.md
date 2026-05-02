---
name: reflect
description: >
  Use when the user says /reflect, or auto-triggered at end of /review or /build when
  reflections.md has 5+ unaddressed entries (3+ is a soft warning — log it but do not auto-run).
  Reads accumulated proposals, consolidates confirmed patterns, and applies controlled improvements
  to repo-local workflow files (auto) or global skill files (user confirmation required).
---

# Reflect — Self-Improvement Workflow

## What this skill does

Reads accumulated proposals from `reflections.md`, identifies confirmed patterns, and applies
controlled improvements to the skill/workflow layer. This is the only safe path for self-improvement.

**Never** rewrite skill files mid-session during a normal review or build run.
**Never** apply proposals that appeared only once without user confirmation.
**Always** prefer repo-local workflow overrides before touching global skill files.

---

## Dynamic Source Loading

Read these files before running the consolidation:

```
~/.agents/context/reflections.md     (global cross-repo proposals — always read)
.kit/context/reflections.md        (repo-local proposals — read when exists)
.kit/context/memory.md             (confirmed patterns already promoted)
~/.agents/instructions.md
```

### Canonical query interface

For orchestrators that need a structured view (count, status, entries) of
the unaddressed reflection backlog before deciding to run /reflect, use:

```powershell
pwsh ~/.agents/tools/reflect-trigger.ps1 -Json
```

Returns `{status, count_repo, count_global, entries, recommended_action}`.
Exit code 2 = `mandatory` (5+ unaddressed). Pre-session and post-session
already wire this in; manual orchestrators should call it before /build,
/review, or /analyze when context allows.

### Automatic mechanical consolidation (no /reflect call needed)

`post-session.ps1` runs `auto-consolidate.ps1` automatically. It handles the
agent-less parts of this skill deterministically:

- **Dedup**: identical {class, pattern} entries merge into one with a count
- **Archive**: entries whose pattern appears in `memory.md` as `Promoted:`
  are dropped (already resolved upstream)
- **Stale**: single-occurrence entries older than 30 days are dropped
- **Auto-promote**: `class:additive` or `class:noise` entries with count ≥ 2
  AND a writable `Suggested target` are appended to that target with a
  marker comment, then archived

After auto-consolidate, the count reflects only entries that genuinely
need judgment (gating, routing, verification). When YOU run /reflect, you
focus on those — not the noise.

You can run the consolidator standalone:

```powershell
pwsh ~/.agents/tools/auto-consolidate.ps1            # apply
pwsh ~/.agents/tools/auto-consolidate.ps1 -DryRun   # preview only
pwsh ~/.agents/tools/auto-consolidate.ps1 -Json     # machine-readable summary
```

`/reflect` (this skill) is now reserved for the **judgment-heavy work** that
auto-consolidate cannot do safely:
- promoting `class:gating` / `class:routing` / `class:verification` entries
  (they change workflow contracts)
- choosing between repo-local vs global scope when both could apply
- rewording pattern text into actual edit content

In practice, most sessions never need /reflect — the mechanical pass keeps
the backlog clean.

**Consolidate both sources.** Repo-local entries target repo-local workflow files. Global entries (`~/.agents/context/reflections.md`) target global skills or `copilot-instructions.md` (user confirmation required for global targets).

---

## Improvement Hierarchy

Apply improvements to the narrowest scope that fixes the problem:

| Scope | File(s) | When to use | Confirmation |
|-------|---------|-------------|-------------|
| 1. Repo-local workflow | `.kit/workflows/analyze.md` / `build.md` / `review.md` | Issue is repo-specific | Auto — apply directly |
| 2. Repo-local shared | `.kit/workflows/shared.md` | Applies across all modes in this repo | Auto — apply directly |
| 3. Global skill | `~/.agents/skills/<name>/SKILL.md` | Universal role/phase issue | Ask user first |
| 4. Global instructions | `~/.agents/instructions.md` | Global routing issue | Ask user first |

**Always start at scope 1. Only escalate when the pattern is clearly not repo-specific.**

---

## Consolidation Workflow

### Step 1 — Read and triage

Read `.kit/context/reflections.md`. For each entry, classify:

| Class | Action |
|-------|--------|
| **Confirmed pattern — additive** (once, concrete evidence) | Eligible — adds a new check/reviewer only, never removes or changes gates |
| **Confirmed pattern — gating/routing** (2+ cross-session occurrences) | Eligible — changes a gate, severity threshold, or routing rule |
| **Single observation — gating/routing** (once) | Leave in reflections, do not promote — wait for recurrence |
| **Already addressed** (fix already in memory.md or a skill file) | Archive — remove from reflections |

**Noise guard**: if unsure whether a change is additive or gating, treat as gating (require 2+). This prevents one noisy session from ratcheting complexity into permanent gates.

### Step 2 — Match pattern to target file

For each confirmed pattern, identify the narrowest target:

- False positive about a repo-specific shape → `.kit/workflows/review.md`
- Missing review category for this domain → `.kit/workflows/review.md`
- Workflow step that consistently fails in this repo → `.kit/workflows/build.md` or `shared.md`
- Role behavior wrong in general (any repo) → `~/.agents/skills/<skill>/SKILL.md`
- Routing rule wrong globally → `~/.agents/instructions.md` (user confirmation required)

### Step 3 — Propose the edit

For each confirmed pattern:
1. State the pattern: what happened, how many times, what file it belongs in
2. State the exact addition, change, or suppression to make
3. If touching a global skill: state why repo-local scope is not sufficient

### Step 4 — Apply (confirmation required for global scope)

- **Repo-local scope (1-2):** Apply directly. Record in `memory.md`.
- **Global scope (3-4):** Present proposed change to user first. Apply on confirmation.

### Step 5 — Clean up reflections

After promoting a pattern:
- **Delete the entry** from `reflections.md` — do not annotate it as "→ promoted". The file should only ever contain unaddressed entries.
- Add a single dated line to `.kit/context/memory.md`: `[DATE] Promoted: [pattern summary] → [target file]`
- This keeps reflections.md lean and memory.md as the audit trail.

### Automatic Trigger

The following skills call this automatically when `reflections.md` has **5+** unaddressed entries:
- `/review` — at end of writeback step
- `/build` — at end of session update step
- `/analyze` — at end of writeback step (step 14)
- `/refactor` — at end of Phase 9

At 5+ entries: **mandatory** — run consolidation before completing the current session.

---

## What counts as a promotable pattern

| Pattern class | Example | Promote when |
|--------------|---------|-------------|
| False positive | "api-reviewer always flags X but it's correct here" | 2+ times |
| Missing domain check | "review never checks evaluator-boundary" | 2+ times, or clearly evidenced |
| Wrong severity | "blob issues always escalate to Critical but are Medium here" | 2+ times |
| Role gap | "adversarial pass misses contract aliases" | Any real missed finding |
| Verification gap | "completion-verifier skips Python test run" | Any single missed verification |
| Role noise | "maintainability-reviewer fires on every trivial change" | 2+ times |

---

## Session Analysis Mode (optional, run after significant build/investigate sessions)

Invoke with `/reflect session` or when explicitly asked to "capture session learnings".
Adapted from feiskyer's `deep-reflector` agent.

This mode reads the current session's private handoff file and extracts durable learnings — distinct from the reflections.md consolidation workflow above.

### What to extract

Read `~/.agents/session-state/{session_id}/handoffs.md` (or the private handoff noted in the shared handoffs index) and identify:

1. **Problems & Solutions** — what broke, root cause, what fixed it, key insight
2. **Code/Architecture Patterns** — design decisions made, why, what alternatives were rejected  
3. **User Preferences** — communication preferences, quality standards, workflow signals (direct quotes where available)
4. **System Understanding** — component interactions confirmed, failure modes discovered, critical paths
5. **Knowledge Gaps** — misunderstandings that occurred, information that was missing, better approaches discovered

### Output

Write a **Session Learning Summary** to the session-private file with these sections populated. Then apply the write gate:

| Finding type | Write to |
|-------------|----------|
| Cross-repo skill pattern | `~/.agents/skills/{skill}/memory.md` |
| Universal workflow gap | `~/.agents/context/reflections.md` |
| Repo-specific architectural fact | `.kit/context/memory.md` |
| User preference (workflow style) | `~/.agents/context/reflections.md` with `[user-preference]` tag |
| One-off session note | Session private handoff only — do not promote |

Apply the same noise guard: single-session observation of a gating pattern → leave in reflections, wait for recurrence. Additive patterns (new check, new expert trigger) can be promoted after a single high-confidence session.

---


- The `## Dynamic Source Loading` sections in any skill
- The `reflections.md` writeback rules themselves
- The verification-before-completion Iron Law
- File guard rules in `shared.md` or `AGENTS.md`
