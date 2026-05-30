# AGENTS.md — Caspar Bannink Agentic Coding Kit

Canonical agent instructions. Any CLI that reads `AGENTS.md` (Codex, Kimi,
Aider, Cline, Cursor, Continue, etc.) gets the right behavior from this file.

## Core operating rules

1. Respect the `.kit` layout (`.kit/context/`, `.kit/workflows/`).
2. Use `.wiki/features.md` and `.wiki/.features` for user-visible capabilities.
3. Treat session handoffs as session-private; repo memory is durable.
4. Prefer:
   - `/plan` before non-trivial implementation
   - `/build` for execution
   - `/review` for audits
   - `/analyze` for multi-angle synthesis
   - `/investigate` for unknown-cause debugging
   - `/refactor` for principle-driven restructuring
   - `/redesign` for greenfield UI / multi-component visual work (swarm-eligible)
   - `/security-review` for adversarial audits (swarm-eligible)
5. Use role-specific repo memory only through the mechanical resolver:
   `pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId {id} -Role {role}`
6. Default execution is **sequential**. Swarms only fire when all three hold:
   parallel-safe verb (audit / explore / port / redesign / pentest), fan-out-able
   scope, explicit user opt-in.

## Cost-aware orchestration

The main session is the orchestrator. It may read directly relevant files to
classify scope, pick a workflow, and write a precise handoff, but it should not
absorb sustained worker context.

- Any real exploration, pattern search, unfamiliar code mapping, or ownership
  tracing should go to `workflow-explorer`.
- Inline coding is for direct answers, commands, and obvious mechanical edits
  across at most 3 files.
- Coding likely to touch more than 3 files, add new files, cross module
  boundaries, or require unfamiliar conventions should use
  `workflow-implementer` or the host's hard implementer variant.
- Long-running implementation, review, and verification should be delegated to
  leaf agents when the harness supports them.

## Memory write routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Repo-local specialist guidance | `.kit/context/agent-memory/{role}.md` or `shared.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session-only | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` (default `~/.agents/session-state`) |

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
- or the same installer bootstrap command above if the repo is missing the whole scaffold

`/bootstrap-harness` is the single high-level init path. It should scaffold the
repo AND run the evidence-based init flows (`git-archaeology`, `kit-init`,
`wiki-init`) so the repo is actually ready for coding afterward.

Do not act as though repo-local memory, wiki requirements, and workflow overrides are available when these files are absent. Continue for quick questions if needed, but warn that the repo is only partially wired into the kit until the scaffold exists.

## Verification freshness

If files change after verification, rerun verification before claiming completion. Prior evidence becomes stale after later edits.

## File layout to respect

```text
.kit/context/
.kit/workflows/
.wiki/
```

## Lifecycle

```
pre-session.ps1 → /plan or /build or … → state-gate enforcement → post-session.ps1
```

- `pre-session.ps1` classifies scope (`ISOLATED` / `SHARED` / `CRITICAL`),
  recommends a tier (`INLINE` / `TARGETED` / `FULL` / `SWARM`), generates a brief.
- `state-gate.ps1` enforces gates and the agent cap.
- `post-session.ps1` is the single owner of handoff registration and evidence.
