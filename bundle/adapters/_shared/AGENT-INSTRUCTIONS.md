# Caspar Bannink Agentic Coding Kit — Agent Instructions

This repo uses the kit. The instructions below apply to any CLI agent (Claude Code,
Codex CLI, Copilot CLI, OpenCode, Kilo Code, or anything else that reads
AGENTS.md / system-prompt files).

## Core operating rules

1. Respect the `.kit` layout in this repo (`.kit/context/`, `.kit/workflows/`).
2. Use `.wiki/features.md` and `.wiki/.features` for user-visible capabilities.
3. Treat session handoffs as session-private; repo memory as durable.
4. Prefer:
   - `/plan` before non-trivial implementation
   - `/build` for execution
   - `/review` for audits
   - `/analyze` for multi-angle research
   - `/investigate` for unknown-cause debugging
   - `/refactor` for principle-driven restructuring
   - `/redesign` for greenfield UI / multi-component visual work (swarm-eligible)
   - `/security-review` for adversarial audits (swarm-eligible)
   - `/goal` for autonomous end-to-end achievement of multi-step goals (classifies type, routes to the correct workflow, iterates until done)
5. Use role-specific repo memory only through the mechanical resolver:
   `pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId {id} -Role {role}`
6. Default execution is **sequential**. Swarms only fire when all three hold:
   verb is parallel-safe (audit / explore / port / redesign / pentest), scope
   classifies as fan-out-able, and the user opts in (`--swarm` or a swarm command).

## Command semantics

- `/plan` — clarify, explore, map files, pressure-test, stop for approval
- `/build` — execute approved plan, review, verify
- `/review` — hierarchical swarm review (sequential implement, parallel reviewers OK)
- `/analyze` — multi-angle feature / idea / architecture evaluation; not for simple factual lookups
- `/investigate` — root-cause-first debugging
- `/refactor` — principle-driven restructuring with consequence tracing
- `/redesign` — multi-component UI work (parallel design agents per component). Locks aesthetic direction via `aesthetic-director` skill if `DESIGN.md` is missing — prevents parallel agents from each defaulting to LLM aesthetic (Inter + purple gradient + rounded cards) and producing variations of one boring look.
- `/security-review` — adversarial audit (parallel attack-class agents)
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
  down to `prompt-synthesizer` or the worker you are about to spawn.

### Prompt synthesis

- Default to direct `router -> worker` handoffs.
- Use `prompt-synthesizer` only when the handoff is genuinely noisy: long
  multi-source context, retry/re-spawn after failure, or a cross-harness handoff
  that needs a tighter brief.
- If `prompt-synthesizer` still finds material ambiguity, route that back to the
  top-level router. It is a compression helper, not a clarification owner or
  spawn decision-maker.

## Non-trivial `/build` discipline

When the host supports subagents/agents, non-trivial `/build` work should
delegate rather than stay inline in the main session.

- one-file mechanical fixes may stay inline
- anything needing more than two source-file reads should delegate exploration
- anything beyond a one-file mechanical edit should delegate implementation
- non-trivial review should delegate reviewer agents when the host supports them
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
- `state-gate.ps1` enforces gates and the agent cap.
- `test-loop.ps1` is the verification heartbeat — runs your test command,
  marks `verification_evidence` gate on pass, escalates on stuck (3-in-a-row
  same failure → exit code 3 + escalation message).
- `edit-with-lint.ps1` applies file edits with linter validation — refuses
  changes that break syntax (auto-detects linter by extension).
- `post-session.ps1` is the single owner of handoff registration and evidence.
  Runs three closure phases automatically: auto-consolidate (mechanical),
  compress-memory (slop prevention), harness-propose (kit-level proposals).

## Self-improvement loop (closes itself)

`post-session.ps1` automatically runs:

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
- **`reflect-trigger.ps1`** — gates on the unaddressed reflection count.
  Status: ok (<3) / soft (3-4) / mandatory (5+, blocks ship in NonInteractive).

Most sessions need no manual `/reflect`. When `harness-propose` does fire,
review with:

```
pwsh ~/.agents/tools/harness-review.ps1                  # list pending
pwsh ~/.agents/tools/harness-review.ps1 -Show <id>       # read full proposal
pwsh ~/.agents/tools/harness-review.ps1 -ProposalId <id> -Action accept|reject|defer -Note '...'
```

The implementation gap is intentional: the kit detects and proposes; you
decide and implement manually. No auto-modification of kit files.

## Startup repo preflight

At session start, check whether the repo has the expected kit scaffold:

- `.kit/context/memory.md`
- `.kit/workflows/`
- `.wiki/index.md`
- `.wiki/features.md`
- `.wiki/.features`

If `.kit` is missing, tell the user the repo is not bootstrapped for the kit yet and suggest:

- `/bootstrap-harness` (preferred when the repo command is available)
- or `pwsh <path-to-agentic-coding-kit>\scripts\install-<host>.ps1 -BootstrapHarness -TargetRepo "<repo>"`

If `.wiki/index.md`, `.wiki/architecture.md`, `.wiki/codebase.md`, `.wiki/features.md`, or `.wiki/.features` is missing, suggest:

- `/bootstrap-harness` if the repo is missing the full scaffold
- or the same installer bootstrap command if the repo is missing the whole scaffold

`/bootstrap-harness` is the single high-level init path. It should scaffold the
repo AND run the evidence-based init flows (`git-archaeology`, `kit-init`,
`wiki-init`) so the repo is actually ready for coding afterward.

Do not act as though repo-local memory, wiki requirements, and workflow overrides are available when these files are absent. Continue for quick questions if needed, but warn that the repo is only partially wired into the kit until the scaffold exists.

## Verification freshness

If files change after verification has been captured, treat the verification as stale and rerun it. The harness should not carry fresh verification evidence across later edits.

## Memory write routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Repo-local specialist guidance | `.kit/context/agent-memory/{role}.md` or `shared.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session-only | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` (default `.kit/session-state` in a bootstrapped repo, else `~/.agents/session-state`, overridable) |

## File layout to respect

```text
.kit/context/         # repo memory + role memory + handoffs index
.kit/workflows/       # repo-specific workflow overrides
.wiki/                  # user-visible feature docs
```

## Tool quick reference

| Tool | Purpose |
|---|---|
| `pre-session.ps1` | Classify scope/tier, generate brief, init session state |
| `post-session.ps1` | Register handoff, run consolidate→compress→propose→gate |
| `state-gate.ps1` | Mark gates, register agents under tier cap, query state |
| `test-loop.ps1` | Run test command, capture output, mark verification gate, detect loops |
| `edit-with-lint.ps1` | Apply file edit with linter validation, atomic write+revert |
| `specialist-memory-resolver.ps1` | Inject role-specific repo memory into spawned agents |
| `mode-profiles.ps1` | Resolve tool/file restrictions for a named agent mode; embed `prompt_block` in subagent prompt |
| `auto-consolidate.ps1` | Dedup/archive/promote reflections (mechanical, no agent) |
| `compress-memory.ps1` | Archive old session dirs, age out history, dedup memory files |
| `harness-propose.ps1` | Detect recurring kit-level patterns, write proposals (no auto-apply) |
| `harness-review.ps1` | List/show/decide on harness proposals |
| `reflect-trigger.ps1` | Gate on unaddressed reflection count |
| `detect-slop.ps1` | Scan for AI-slop patterns in code; -Fix for safe cosmetic fixes |
| `scope-classifier.ps1` | ISOLATED / SHARED / CRITICAL scope from changed files |
| `swarm-classifier.ps1` | sequential / swarm-review / swarm-fanout from verb+scope+opt-in |
| `playwright-runner.ps1` + `.py` | Capture screenshots from a YAML screen-flow |
| `visual-diff.ps1` | Pair before/after screenshots, produce diff PNGs |
| `context-bloat-guard.ps1 -RepoRoot . -AutoFix -Json` | Context size check — run at session start and every 3 iterations in goal loops |
| `multi-pass-review.ps1 -SessionId <id> -Passes 3` | Multi-pass shuffled review for large diffs (>5 files) — 2× bug detection rate |
| `test-loop-runner.ps1 -SessionId <id> -TestCommand "<cmd>" -MaxRounds 5` | Iterate-until-pass test runner for /test-gen and verification loops |
| `memory-inbox.ps1 -Action collect -SessionId <id>` | Collect learned patterns into memory inbox — run at session end |

Read the docs in the kit for the full operating model.
