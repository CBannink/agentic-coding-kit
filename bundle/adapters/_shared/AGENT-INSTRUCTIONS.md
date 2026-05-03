# Caspar Bannink Agentic Coding Kit — Agent Instructions

This repo uses the kit. The instructions below apply to any CLI agent (Claude Code,
Codex CLI, Copilot CLI, OpenCode, Kilo Code, or anything else that reads
AGENTS.md / system-prompt files).

## Core operating rules

1. Respect the `.codex` layout in this repo (`.kit/context/`, `.kit/workflows/`).
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
5. Use role-specific repo memory only through the mechanical resolver:
   `pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId {id} -Role {role}`
6. Default execution is **sequential**. Swarms only fire when all three hold:
   verb is parallel-safe (audit / explore / port / redesign / pentest), scope
   classifies as fan-out-able, and the user opts in (`--swarm` or a swarm command).

## Command semantics

- `/plan` — clarify, explore, map files, pressure-test, stop for approval
- `/build` — execute approved plan, review, verify
- `/review` — hierarchical swarm review (sequential implement, parallel reviewers OK)
- `/analyze` — multi-angle synthesis
- `/investigate` — root-cause-first debugging
- `/refactor` — principle-driven restructuring with consequence tracing
- `/redesign` — multi-component UI work (parallel design agents per component). Locks aesthetic direction via `aesthetic-director` skill if `DESIGN.md` is missing — prevents parallel agents from each defaulting to LLM aesthetic (Inter + purple gradient + rounded cards) and producing variations of one boring look.
- `/security-review` — adversarial audit (parallel attack-class agents)

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

## Memory write routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Repo-local specialist guidance | `.kit/context/agent-memory/{role}.md` or `shared.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session-only | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` (default `~/.agents/session-state`) |

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

Read the docs in the kit for the full operating model.
