---
name: investigate
model: gpt-5.4
description: >
  Use when the user says /investigate or asks to debug, diagnose, trace, or root-cause
  something that isn't a build task — flaky CI, provider incidents, dependency drift,
  cross-repo contract failures, environment issues, or any scenario where the cause is
  unknown. Runs hypothesis-driven investigation with evidence capture.
  NO automatic memory mutation. NO workflow rule changes. Evidence only.
  Orchestrator: gpt-5.4. Explorers: gpt-5.4-mini (0.33x cost).
  gstack source: ~/.agents/workflows/plugins/gstack/investigate/SKILL.md
---

# Investigate Workflow

## What this skill is for

Debugging and ops work that doesn't fit /build, /analyze, or /review:
- Flaky CI pipelines, intermittent test failures
- Provider/API incidents, rate-limit patterns, degraded service behaviour
- Dependency drift (transitive version conflicts, breaking upgrades)
- Cross-repo contract failures (type drift, schema mismatch, API version skew)
- Environment issues (missing env vars, wrong config, port conflicts)
- Performance regressions with unknown cause
- Any scenario where the root cause is genuinely unknown

**Not for**: implementing features (/build), reviewing code (/review), or broad research (/analyze).

---

## Investigation Tier (judge before spawning any agents)

| Tier | Pick when | Agent policy |
|------|-----------|-------------|
| **INLINE** | Cause is plausible from a single read (wrong config, obvious typo, missing env var). 1–2 hypotheses at most. | Orchestrator states hypotheses inline, reads evidence directly, confirms root cause without sub-agents. |
| **TARGETED** | 2–4 competing hypotheses, OR uncertainty about which layer is failing, OR requires reading 3+ files across modules | 1 `hypothesis-generator` pass, max 2 `evidence-explorer` batches. Stop when root cause confirmed — no further agents. |
| **FULL** | Flaky/non-deterministic, cross-system, provider incident, dependency drift, or after 2+ failed hypothesis cycles | Full loop: hypothesis-generator + parallel evidence-explorers + elimination + optional cross-provider sanity check. |

**Default when unsure: TARGETED, not FULL.** FULL is for genuinely unknown multi-system causes — not for comfort.

### Agent-spawn gate (apply before every sub-agent dispatch)

Before spawning any agent, answer: **"Can I answer this by reading 1–2 files or checking 1 command directly?"**
- **YES** → do it inline. Do not spawn.
- **NO** → spawn the minimum agents needed for the specific gap.

---



From gstack-investigate:

```
1. STATE THE SYMPTOM precisely — what is the observed failure, error, or anomaly?
2. LIST HYPOTHESES — enumerate competing root causes ordered by likelihood
3. CHEAPEST TEST — design the cheapest test that distinguishes between them
4. ELIMINATE WITH EVIDENCE — run the test, read the output, eliminate hypotheses
5. FIX ONLY AFTER ROOT CAUSE IS CONFIRMED — never fix before you know the cause
```

Never skip step 2 (listing hypotheses) — the cheapest test only exists relative to which hypotheses it distinguishes.

---

## Load Context First (graceful — skip missing files)

- `~/.agents/skills/investigate/memory.md` — cross-repo root-cause patterns; read before generating hypotheses
- `AGENTS.md`
- `.codex/workflows/shared.md`
- `.codex/context/memory.md` — known patterns, architecture constraints, verified commands
- `.codex/context/handoffs.md` — recent changes that may have caused this

---

## Agent Matrix

### Phase 1 — Symptom Capture

Before any investigation, state the symptom in structured form:

```
SYMPTOM: [what is failing or behaving unexpectedly — exact error message or behaviour]
WHEN: [when did it start? after what event?]
SCOPE: [always? sometimes? specific conditions?]
ALREADY RULED OUT: [what has been tried without success]
```

### Phase 2 — Hypothesis Generation

- `hypothesis-generator` (gpt-5.4) — **TARGETED/FULL only**; **INLINE**: orchestrator lists hypotheses inline, no sub-agent
  Purpose: enumerate all plausible root causes. At least 3 hypotheses. Order by likelihood.
  Output format:
  ```
  H1: [hypothesis] — likelihood: HIGH/MED/LOW — evidence for: [why suspect this]
  H2: ...
  ```

### Phase 3 — Evidence Gathering

- `evidence-explorer` (gpt-5.4-mini, parallel when multiple hypotheses)
  Purpose: gather concrete facts for each hypothesis — logs, config, code, test output, git history.
  Rules: gather facts only. No conclusions. No fixing.

### Phase 4 — Elimination

For each hypothesis, state:
- TESTED HOW: what evidence was gathered
- RESULT: confirmed / eliminated / inconclusive
- REMAINING: list of surviving hypotheses after elimination

If no hypothesis survives: generate new hypotheses and repeat from Phase 2.

### Phase 5 — Root Cause Confirmation

State the confirmed root cause:
```
ROOT CAUSE: [exact mechanism — not a symptom restatement]
EVIDENCE: [file:line or log:timestamp or config:key that proves it]
CONFIDENCE: HIGH / MEDIUM (if medium, state what would make it HIGH)
```

Do NOT proceed to fix until confidence is HIGH.

### Phase 5.5 — Ownership Verification (BLOCKING for `/build` handoff)

Before producing a Build Brief, verify the **owner file** for every claimed defect:

```
OWNER VERIFIED: [file:line/function that directly owns the broken behaviour]
NEARBY FALSE OWNER RULED OUT: [adjacent caller/callee/presenter file:line checked and why it is not the owner]
PROOF TYPE: [failing test output + source read, targeted grep, log/config, etc.]
```

Rules:
- If the symptom is user-visible output drift, inspect both the **producer** and the **presentation layer** before naming the owner.
- If the symptom is wrong derived data, inspect both the **normalizer/calculator** and the **caller that surfaces the result**.
- Never hand `/build` a file in `Fix scope` unless its ownership has been verified with file:line evidence.
- If two files remain plausible owners, confidence is **not HIGH** yet. Keep investigating.

### Phase 6 — Fix (if in scope)

Only after root cause is confirmed:
- Propose the minimal fix (do not improve unrelated code)
- If the fix requires /build (multi-file change with tests): hand off to /build with a brief
- If the fix is a config change or one-liner: apply directly and verify

### Phase 7 — Evidence Capture (NO automatic mutation)

After investigation:

**Write to `handoffs.md`** (operational continuity only):
```
## Investigation: [SYMPTOM] — [DATE]
- Root cause: [confirmed cause]
- Evidence: [file:line or log reference]
- Fix applied: [what was done, or "handed off to /build"]
- Remaining unknowns: [any unresolved questions]
```

**Write router + skill memory retrieval**: follow `~/.agents/context/writeback-protocol.md` and `~/.agents/context/skill-memory-index.json`.
**Workflow evidence**: follow `~/.agents/context/workflow-evidence-protocol.md` and record mode, repo context used, hypothesis/evidence commands, major agents spawned/skipped, and write decisions.

**DO NOT auto-promote to `reflections.md`** unless the investigation reveals a genuine workflow gap. Use `~/.agents/context/reflection-protocol.md`.

**NEVER auto-modify workflow files** during an investigation.

**When investigation concludes with a fix that requires /build** (multi-file change, tests needed, non-trivial scope), append a **Build Brief** in the session-private handoff file:

```
## Build Brief [YYYY-MM-DD]
- Source: investigate
- Symptom: [what was failing]
- Root cause: [confirmed mechanism, file:line]
- Evidence confidence: HIGH / MEDIUM
- Fix scope: [exact files to change, what to change]
- Ownership proof: [for each file in fix scope: why this file owns the defect]
- False owners ruled out: [nearby files checked and why they are not the right fix target]
- Known blast radius: [what else may be affected]
- Modules already mapped — /build Phase 0 can skip: [list]
- Next steps for /build: [ordered task list]
```

For backward compatibility, `/build` may also accept the legacy `## Investigation-to-Build Brief [YYYY-MM-DD]` header, but new sessions should write `## Build Brief [YYYY-MM-DD]`.

Before the final diagnosis, include a compact **Workflow Evidence** block.

---

## Rules

- Never fix before root cause is confirmed at HIGH confidence.
- Never produce a "suspected cause" fix — that is a guess, not a diagnosis.
- Never emit a Build Brief with an unverified fix owner. Wrong-file handoffs are investigation failures, not acceptable ambiguity.
- If the investigation reaches 3 failed hypothesis cycles, stop and ask the user for more context.
- Evidence from logs, test output, git history, and config always beats code reading for ops issues.
- If the issue is non-deterministic (flaky), run the failing scenario 3+ times to characterise the failure rate before hypothesising.

## Model Routing

| Role | Model | Why |
|------|-------|-----|
| Orchestrator + hypothesis generation | `gpt-5.4` | Multi-hop causal reasoning across large evidence sets |
| Evidence explorer | `gpt-5.4-mini` | Fast parallel tool-calling; GitHub-recommended for agentic codebase exploration |
| Cross-provider sanity check (optional) | `gpt-5.4` | Different training catches different systemic patterns; invoke when hypothesis list is exhausted |

## Fallback Ladder

| Role | Primary | Fallback |
|------|---------|---------|
| Orchestrator | `gpt-5.4` | `claude-sonnet-4.6` |
| Explorer | `gpt-5.4-mini` | `claude-sonnet-4.6` |
