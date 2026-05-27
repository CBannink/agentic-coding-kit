# Claude Code Adapter — Caspar Bannink Agentic Coding Kit

Same operating rules as the rest of the kit; see
`bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` for the canonical body.

## Core operating rules

1. Respect the `.kit/` layout (`.kit/context/`, `.kit/workflows/`).
2. Use `.wiki/features.md` and `.wiki/.features` for user-visible capabilities.
3. Treat session handoffs as session-private and repo memory as durable.
4. Prefer:
   - `/plan` before non-trivial implementation
   - `/build` for execution
   - `/review` for audits
   - `/analyze` for multi-angle synthesis
   - `/investigate` for unknown-cause debugging
   - `/refactor` for principle-driven restructuring
   - `/redesign` for greenfield UI / multi-component visual work (swarm-eligible)
   - `/security-review` for adversarial audits (swarm-eligible)
5. Use role-specific repo memory only through the mechanical resolver path:
   `pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId {id} -Role {role}`
6. Default execution is **sequential**. Swarms only fire when verb is
   parallel-safe, scope is fan-out-able, and the user opts in.

## Command semantics

- `/plan` — clarify, explore, map files, pressure-test, stop for approval
- `/build` — execute approved plan, review, verify
- `/review` — hierarchical review (sequential implement, parallel reviewers OK)
- `/analyze` — multi-angle synthesis
- `/investigate` — root-cause-first debugging
- `/refactor` — principle-driven restructuring
- `/redesign` — multi-component UI work (swarm-eligible). Locks aesthetic via `aesthetic-director` if no `DESIGN.md` exists.
- `/security-review` — adversarial audit (swarm-eligible)

## Frontend aesthetic direction

Greenfield UI work in `/build` or `/redesign` automatically checks for `DESIGN.md`. When absent, the `aesthetic-director` skill runs first — proposes 2-3 named directions, user picks, writes a locked `DESIGN.md` (typography, OKLCH palette, density, motion, banned-defaults list). `ux-driver` and `ui-driver` read this and refuse to silently default. Without a locked direction, parallel design agents converge on the same Inter + purple-gradient + rounded-2xl LLM default. The 5-line shortcut: paste an `<always_use_X_theme>` block into this `CLAUDE.md`.

## Startup repo preflight

At session start, check whether the repo has the expected kit scaffold:

- `.kit/context/memory.md`
- `.kit/workflows/`
- `.wiki/index.md`
- `.wiki/features.md`
- `.wiki/.features`

If `.kit` is missing, tell the user the repo is not bootstrapped for the kit yet and suggest:

- `/bootstrap-harness` (preferred when the repo command is available)
- or `pwsh <path-to-agentic-coding-kit>\scripts\install.ps1 -BootstrapHarness -TargetRepo "<repo>"`

If `.wiki/index.md`, `.wiki/architecture.md`, `.wiki/codebase.md`, `.wiki/features.md`, or `.wiki/.features` is missing, suggest:

- `/bootstrap-harness` if the repo is missing the full scaffold
- or the same installer bootstrap command above if the repo is missing the whole scaffold

`/bootstrap-harness` is the single high-level init path. It should scaffold the
repo AND run the evidence-based init flows (`git-archaeology`, `kit-init`,
`wiki-init`) so the repo is actually ready for coding afterward.

Do not act as though repo-local memory, wiki requirements, and workflow overrides are available when these files are absent. Continue for quick questions if needed, but warn that the repo is only partially wired into the kit until the scaffold exists.

## Verification freshness

If files change after verification, rerun verification before you claim completion. Do not reuse stale evidence across later edits.

## Claude `/build` execution discipline

For Claude Code, `/build` should normally use the main session as a **coordinator**
and push actual exploration/coding/review into the installed workflow agents.

- If the task needs more than **two source-file reads** to understand, spawn
  `workflow-explorer`.
- If the task changes more than one source file, or anything beyond a one-file
  mechanical fix, spawn `workflow-implementer`.
- Use `workflow-reviewer`, `workflow-skeptic`, and `workflow-ui-qa` for the
  matching review passes instead of keeping review entirely inline.
- After exploration synthesis, the main session should stop reading source
  files. Downstream reads belong in the delegated subagents.
- If the main session is using an expensive/reasoning-heavy runtime, direct repo-code editing should be
  treated as the exception, not the default.

## File layout to respect

```text
.kit/context/         # repo memory + role memory + handoffs index
.kit/workflows/       # repo-specific workflow overrides
.wiki/                  # user-visible feature docs
```

Read the docs in this kit for the full operating model.
