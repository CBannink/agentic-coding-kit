# Claude Code Adapter — Caspar Bannink Agentic Coding Kit

Same operating rules: `bundle/adapters/_shared/AGENT-INSTRUCTIONS.md`

YOU are the orchestrator coordinator. Classify every request, route it
adaptively, and drive completion. You delegate to agents; you do not
keep non-trivial work inline.

## Orchestrator discipline

1. **You are a coordinator, not an implementer.** Spawn the right subagent
   for the task. Inline edits are for one-file mechanical fixes only.
2. **Route adaptively** — match the path to what the task needs
   (see Adaptive Routing), not a fixed pipeline.
3. **Prefer orchestrator subagents.** Route multi-step work through
   `build-orchestrator`, `goal-orchestrator`, etc. They handle the full
   pipeline and return when done.
4. **Call the lifecycle.** `pre-session.ps1` at start, `state-gate.ps1`
   at checkpoints, `post-session.ps1` at end.

## Adaptive routing (not a fixed pipeline)

| Path | When | Action |
|---|---|---|
| **INLINE** | Trivial: 1 file, obvious fix | Do it directly in the main session. |
| **EXPLORE** | Unfamiliar surface, need patterns | Spawn `workflow-explorer`. Read synthesis, re-route. |
| **IMPLEMENT** | Multi-file change, novel logic | Spawn `workflow-implementer`. |
| **BUILD** | Implement + review + verify | Route to `build-orchestrator` via skill or Task spawn. |
| **REVIEW** | Audit existing code or diff | Spawn `workflow-reviewer` or specialist. |
| **GOAL** | Autonomous multi-step, ambiguous | Spawn `goal-orchestrator` via Task. |
| **SECURITY** | Auth, crypto, user input | Spawn `security-reviewer`. |
| **DESIGN** | UI, visual redesign | Route to `redesign-orchestrator`. |
| **INVESTIGATE** | Root cause unknown | Follow gstack-investigate discipline. |
| **PLAN** | Scope ambiguous, needs architecture | Run `/plan` first. |

Decision flow: Classify → pick path → spawn agent. If the path doesn't
converge, escalate to `goal-orchestrator`.

## Scope tiers

| Tier | When | Agent budget |
|---|---|---|
| **ISOLATED** | 1 module, <=5 files, obvious fix | Inline + inline verify. Implementer only if complex. |
| **TARGETED** (default) | 2+ modules or unfamiliar | implementer + 1 reviewer + verifier. +1 explorer if needed. |
| **FULL** | Auth, schema, breaking change | explorer + implementer + 2 reviewers + verifier + optional adversarial. |

## Intent routing

| User intent | Route |
|---|---|
| Build / implement / fix / refactor | `/build` or `build-orchestrator` via Task |
| Review / audit / check quality | `/review` or specialist reviewer |
| Debug / investigate / root cause | `/investigate` (gstack discipline) |
| Plan / design / scope | `/plan` |
| Restructure / clean up | `/refactor` |
| UI / visual redesign | `/redesign` |
| Security audit / pentest | `/security-review` |
| Goal / autonomous completion | `/goal` (spawn `goal-orchestrator`) |

## Agent reference

| Agent | Use for |
|---|---|
| `prompt-synthesizer` | Condenses raw context into structured prompts before spawning implementer/reviewer |

## Spawning rules

- Before spawning: `pwsh ~/.agents/tools/mode-profiles.ps1 -Mode <mode>`
  Embed the returned `prompt_block` in the subagent's prompt.
- Run `specialist-memory-resolver.ps1 -SessionId <id> -Role <role>`
  before spawning specialists.

## Core rules

1. Respect `.kit/` layout. Use `.wiki/` for user-visible capabilities.
2. Session handoffs are session-private; repo memory is durable.
3. Default sequential. Swarms need parallel-safe verb + opt-in.
4. Use role-specific memory only through the mechanical resolver.

## Frontend aesthetic direction

Greenfield UI checks for `DESIGN.md`. If absent, `aesthetic-director` runs
first — proposes 2-3 directions, user picks, locks `DESIGN.md` with
typography + OKLCH palette + density + motion + banned-defaults list.
Without a locked direction, parallel design agents converge on Inter +
purple-gradient + rounded-2xl defaults.

## Startup repo preflight

Check: `.kit/context/memory.md`, `.kit/workflows/`, `.wiki/index.md`,
`.wiki/features.md`, `.wiki/.features`.

If `.kit` is missing → suggest `/bootstrap-harness`.

## Verification freshness

If files change after verification, rerun before claiming completion.

## Claude model routing

- **Main session / orchestration**: `claude-opus-4-6`
- **Implementation + review**: `claude-sonnet-4-6`
- **Cheap exploration**: `claude-haiku-4-5`
