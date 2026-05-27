---
name: swarm
description: Fan-out/reduce workflow for parallel-safe work such as repo-wide audits, greenfield UI, security reviews, and bulk migrations.
---

# Swarm Skill — Fan-Out → Reduce

Use this skill ONLY when `swarm-classifier.ps1` returns `mode: swarm-fanout`.
Do not use it for focused features, bug fixes, schema work, or anything in
`CRITICAL` scope.

## When to use

- **Greenfield UI** — designing a new product / page / dashboard from scratch,
  many components, no existing tight coupling
- **Repo-wide audit** — security scan, dead-code, dep upgrade, license audit
- **Security review** — STRIDE / OWASP fan-out by attack class
- **Ethical hacking sweep** — per attack vector, independent
- **Multi-perspective review** — sec / perf / UX / maintainability concurrently
- **Bulk migration** — per-file or per-module port to new API/lib/framework
- **Manual review army** — many concurrent angles, single synthesizer

## When NOT to use

- Targeted feature work (one feature, tight cross-file coupling)
- Bug fix — sequential lineage matters more than breadth
- Schema migration — order of operations IS the work
- Anything where Agent N's output is Agent N+1's input
- Small diffs (<200 lines) — coordination cost > gain

## Steps

### 1. Confirm eligibility

```powershell
pwsh ~/.agents/tools/swarm-classifier.ps1 -Task "<task>" -Scope <scope> -FileCount <n>
```

If `mode != swarm-fanout`, drop back to sequential `/build` or `/review`.

### 2. Decompose into independent items

The decomposition is the most important step. Bad decomposition = swarm hurts.

Good decomposition:
- one component per agent
- one screen per agent
- one attack class per agent
- one module per agent
- one design direction per agent

Bad decomposition:
- one phase of a single component per agent (sequencing, not parallel)
- one piece of a tightly-coupled feature per agent (clobber)

Write the item list before spawning. Keep it visible.

### 3. Spawn fan-out agents

For each item, spawn one agent with:
- the item's narrow scope
- repo-specialist memory injection via `specialist-memory-resolver.ps1`
- a clear "do not widen scope" instruction
- output expectations: structured JSON or markdown the synthesizer can ingest

Cap: agent count must stay under the SWARM tier cap (24) registered in
`state-gate.ps1`. Run:

```powershell
pwsh ~/.agents/tools/state-gate.ps1 -SessionId $SessionId -AddAgent "$role-$item" -EnforceAgentCap
```

after each spawn.

### 4. Synthesize

One synthesizer agent reads all N outputs and produces:
- deduplicated findings / changes / proposals
- explicit conflicts surfaced (not hidden)
- a single coherent merged artifact

The synthesizer is sequential. Do not parallelize this step.

### 5. Verify

One verifier agent confirms:
- all original items were covered
- the synthesized output is internally consistent
- no contradictions between fan-out agents survived
- the verification gate from the underlying mode (`/build`, `/review`, etc.)
  is satisfied

Run the same verification commands you'd run for sequential work.

### 6. Write evidence

Record swarm-specific evidence:

```powershell
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId $SessionId -Tier "SWARM" -TierReason "<from classifier>"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId $SessionId -AddNote "swarm:fanout|N=<count>|items=<list>"
```

## Variants

### swarm-review (lighter)

Sequential implementer + N parallel reviewers. Use when:
- task is sequential (one author, one feature)
- but review breadth would help (sec + perf + UX angles)

This is the **right default for most polish-quality work**. Cheaper and
safer than full fan-out.

### swarm-iterate (for design)

Used by `/redesign` with the `playwright-explorer` skill. Each iteration:
1. screenshot current state
2. fan out one design-driver per screen / component
3. apply changes
4. re-screenshot
5. fan out one critique per change
6. converge

See the `design-driver` and `playwright-explorer` skills.

## Failure modes to watch

- **Decomposition that isn't independent** — fan-out edits clobber each other
- **Synthesizer hides conflicts** — surface them, don't smooth them
- **No verifier** — swarm output is not self-checking
- **Agent count creep** — cap is 24; if you need more, your decomposition is wrong
