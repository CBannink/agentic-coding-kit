# Caspar Bannink Agentic Coding Kit — Agent Instructions

This repo uses the kit. The instructions below apply to any CLI agent (Claude Code,
Codex CLI, Copilot CLI, OpenCode, or anything else that reads
AGENTS.md / system-prompt files).

## Core operating rules

1. Start from the current request and current code.
2. Do not preload `.kit`, `.wiki`, handoffs, history, reflections, or memory files.
3. Use `.wiki/index.md` only as an on-demand index when architecture, feature,
   or principle context is needed.
4. Treat `.kit/context/patterns.md` and old role-specific context as optional
   manual guidance, not normal startup context.
5. Prefer:
   - `/plan` before non-trivial implementation
   - `/build` for execution
   - `/review` for audits
   - `/analyze` for multi-angle research
   - `/investigate` for unknown-cause debugging
   - `/refactor` for principle-driven restructuring
   - `/redesign` for greenfield UI / multi-component visual work (swarm-eligible)
   - `/security-review` for adversarial audits (swarm-eligible)
   - `/goal` for autonomous end-to-end achievement of multi-step goals (classifies type, routes to the correct workflow, iterates until done)
6. Default execution is **sequential**. Swarms only fire when all three hold:
   verb is parallel-safe (audit / explore / port / redesign / pentest), scope
   classifies as fan-out-able, and the user opts in (`--swarm` or a swarm command).

## Command semantics

`/build` is the test-set-first loop: minimal indexed context, expected test set,
implementation with tests, fresh verification, unified review, and repair.

- `/plan` — clarify, explore, map files, pressure-test, stop for approval
- `/build` — context if needed, implement, verify, unified review, repair loop
- `/review` — unified review with false-positive checking
- `/analyze` — multi-angle feature / idea / architecture evaluation; not for simple factual lookups
- `/investigate` — root-cause-first debugging
- `/refactor` — principle-driven restructuring with consequence tracing
- `/redesign` — multi-component UI work (parallel design agents per component). Locks aesthetic direction via `aesthetic-director` skill if `DESIGN.md` is missing — prevents parallel agents from each defaulting to LLM aesthetic (Inter + purple gradient + rounded cards) and producing variations of one boring look.
- `/security-review` — authorized trust-boundary audit
- `/goal` — thin autonomous wrapper; the active orchestrator owns success criteria and convergence, routes to the correct workflow, and iterates by workflow pass until the goal is provably achieved

## Workflow source of truth

The **global workflow skills** are the canonical source of behavior. Adapter
files are transport layers only:

- top-level host prompts should stay small and do **routing first**
- command files should be thin wrappers around the matching workflow skill
- adapter docs should explain host capabilities, not redefine workflow semantics
- adapter-specific agent names may differ, but the workflow contract should not

If an adapter starts behaving differently from the global workflow skill, treat
that as harness drift and fix the source-of-truth problem rather than layering
more adapter-specific exceptions.

## Two-stage routing model

Every host should make the same two decisions in the same order:

1. **Intent** — which workflow owns this request? (`/build`, `/review`,
   `/goal`, `/investigate`, etc.)
2. **Execution mode** — should this stay inline or load the heavy workflow?

Use `scope` as the bridge between the two:

| Scope class | Default execution mode | Meaning |
|---|---|---|
| `isolated` | `inline` | one-file, obvious, no shared interface or new file |
| `shared` | `targeted` | bounded multi-file or unfamiliar-but-normal change |
| `critical` | `full` | auth, schema, public contract, or cross-cutting risk |

### Inline path

- Do **not** read the heavy workflow skill just to confirm a trivial fix.
- Answer or edit directly under the one-file gate.
- Escalate to `targeted` immediately if the edit/create gate fails.

### Workflow path

Only after the router chooses a workflow should it load the heavy workflow body.
Pass the handoff explicitly in the prompt or session context:

- `WORKFLOW_MODE: inline | targeted | full`
- `SCOPE_CLASS: isolated | shared | critical`
- `ROUTING_REASON: <why this mode was chosen>`

The loaded workflow should **honor that handoff**. It may escalate mode with
evidence, but it should not reopen the `inline vs workflow` question unless the
user invoked the workflow directly and no handoff exists.

### Clarification gate

Before loading a heavy workflow, check whether the request is clear enough to
route safely.

- If ambiguity would change **scope**, **workflow choice**, **success
  criteria**, or the **verification command**, ask **one focused clarification**
  first.
- If the ambiguity is minor and does not materially change execution, state the
  assumption and continue.
- The top-level router owns clarification. Do **not** push this responsibility
  down to another worker.

## Non-trivial `/build` discipline

When the host supports subagents/agents, non-trivial `/build` work should
delegate rather than stay inline in the main session.

- one-file mechanical fixes may stay inline
- anything needing more than two source-file reads should delegate exploration
- anything beyond a one-file mechanical edit should delegate implementation
- before implementation, define the expected test set: unit, integration,
  contract, and E2E where feasible, with mock data/fixtures for external
  systems and edge cases
- if E2E is infeasible, record why and use the nearest integration, contract,
  or workflow test that exercises the behavior
- non-trivial review should delegate to `code-quality-reviewer`; add
  `security-reviewer` only for real trust-boundary risk
- after exploration synthesis, the main session should stop reading source files

## Mode profiles

When spawning subagents, resolve their mode profile first:

```
pwsh ~/.agents/tools/mode-profiles.ps1 -Mode <mode>
```

Embed the returned `prompt_block` in the subagent's system prompt. Mode profiles
enforce tool and file restrictions per role. Repos can override built-in profiles
via `.kit/modes/{mode}.json` (fields merged on top; only include what you want to
change).

Built-in modes: `debug`, `architect`, `reviewer`, `implementer`, `explorer`,
`security-reviewer`.

## Frontend aesthetic direction

When `/build` or `/redesign` introduces greenfield UI, the kit checks for `DESIGN.md` first. If missing, the `aesthetic-director` skill runs as Step 0 of the visual gate — proposes 2-3 named directions (Swiss Minimalism, Editorial, Brutalism, Glassmorphism, Dark OLED Luxury, Cyberpunk, etc.), user picks, locks DESIGN.md with typography pairing + OKLCH palette + density + motion + a mandatory **banned-defaults list**. Downstream `ux-driver` and `ui-driver` read DESIGN.md and refuse to silently substitute generic taste when it's missing. Lightweight alternative: paste a 5-line `<always_use_X_theme>` block in CLAUDE.md / AGENTS.md and skip the skill.

## Session lifecycle

```
pre-session.ps1 → /plan or /build or … → state-gate enforcement → post-session.ps1
```

- `pre-session.ps1` classifies scope (`ISOLATED` / `SHARED` / `CRITICAL`),
  recommends a tier (`INLINE` / `TARGETED` / `FULL` / `SWARM`), generates a brief.
- `state-gate.ps1` enforces verification/agent-cap gates. Memory, wiki,
  handoff, and reflection writes are not implementation-completion gates.
- `test-loop.ps1` is the verification heartbeat — runs your test command,
  marks `verification_evidence` gate on pass, escalates on stuck (3-in-a-row
  same failure → exit code 3 + escalation message).
- `edit-with-lint.ps1` applies file edits with linter validation — refuses
  changes that break syntax (auto-detects linter by extension).
- `post-session.ps1` registers handoffs and evidence. Self-improvement and
  writeback tools are manual maintenance, not lifecycle gates.

## Manual self-improvement

These tools remain available when explicitly doing maintenance:

- **`auto-consolidate.ps1`** — dedups identical reflections, archives
  promoted-and-resolved, drops single-occurrence stale entries, auto-promotes
  additive patterns with count≥2 to the relevant repo workflow file.
- **`compress-memory.ps1`** — archives session-state dirs >60 days, ages out
  history.md entries >90 days, dedups memory.md and skill memory files,
  surfaces soft-limit warnings.
- **`harness-propose.ps1`** — when a kit-level failure pattern recurs 5+
  total times AND 3+ within 30 days AND matches kit vocabulary, writes a
  proposal markdown file. **Never auto-applies.** Surfaces a yellow banner
  at session end with explicit review commands. Decisions stick.
- **`reflect-trigger.ps1`** — reports unaddressed reflection count for manual
  maintenance.

Normal build/review/refactor/redesign/security workflows do not run these tools
or block on reflection backlog. When reviewing harness proposals manually, use:

```
pwsh ~/.agents/tools/harness-review.ps1                  # list pending
pwsh ~/.agents/tools/harness-review.ps1 -Show <id>       # read full proposal
pwsh ~/.agents/tools/harness-review.ps1 -ProposalId <id> -Action accept|reject|defer -Note '...'
```

The implementation gap is intentional: the kit detects and proposes; you
decide and implement manually. No auto-modification of kit files.

For normal coding sessions, do not bulk-read `.kit/context`, session handoffs,
or the whole `.wiki` tree at startup. If current code is not enough, use
`.wiki/index.md` as the on-demand knowledge-base index, then pull only the
specific file needed for architecture, feature behavior, or principles.

## Verification freshness

If files change after verification has been captured, treat the verification as stale and rerun it. The harness should not carry fresh verification evidence across later edits.

## File layout to respect

```text
.kit/context/patterns.md # optional focused repo guidance
.kit/workflows/          # repo-specific workflow overrides
.wiki/index.md           # on-demand index into architecture/features/principles
```

## Tool quick reference

| Tool | Purpose |
|---|---|
| `pre-session.ps1` | Classify scope/tier, generate brief, init session state |
| `post-session.ps1` | Register handoff and session evidence |
| `state-gate.ps1` | Mark gates, register agents under tier cap, query state |
| `test-loop.ps1` | Run test command, capture output, mark verification gate, detect loops |
| `edit-with-lint.ps1` | Apply file edit with linter validation, atomic write+revert |
| `mode-profiles.ps1` | Resolve tool/file restrictions for a named agent mode; embed `prompt_block` in subagent prompt |
| `auto-consolidate.ps1` | Manual dedup/archive/promote reflections |
| `compress-memory.ps1` | Manual archive old session dirs, age out history, dedup memory files |
| `harness-propose.ps1` | Manual recurring kit-level proposal generation |
| `harness-review.ps1` | List/show/decide on harness proposals |
| `reflect-trigger.ps1` | Report unaddressed reflection count |
| `detect-slop.ps1` | Scan for AI-slop patterns in code; -Fix for safe cosmetic fixes |
| `scope-classifier.ps1` | ISOLATED / SHARED / CRITICAL scope from changed files |
| `swarm-classifier.ps1` | sequential / swarm-review / swarm-fanout from verb+scope+opt-in |
| `playwright-runner.ps1` + `.py` | Capture screenshots from a YAML screen-flow |
| `visual-diff.ps1` | Pair before/after screenshots, produce diff PNGs |
| `context-bloat-guard.ps1 -RepoRoot . -Json` | Context size report for manual maintenance |
| `multi-pass-review.ps1 -SessionId <id> -Passes 3` | Manual compatibility tool; not default review routing |
| `test-loop-runner.ps1 -SessionId <id> -TestCommand "<cmd>" -MaxRounds 5` | Iterate-until-pass test runner for /test-gen and verification loops |
| `memory-inbox.ps1 -Action collect -SessionId <id>` | Manual collection of learned patterns into memory inbox |

Read the docs in the kit for the full operating model.
