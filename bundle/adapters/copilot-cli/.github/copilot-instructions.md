# GitHub Copilot Instructions -- Caspar Bannink Agentic Coding Kit

Copilot Chat / Copilot CLI reads this file. Copilot CLI shipped native
session/tool hooks (Jan 2026, v0.0.397) and custom agents (Jan 2026,
v0.0.396) plus subagents (Feb 2026, v0.0.406). The kit installs those
surfaces when present:

- Hooks (repo scope only, per docs): `<repo>/.github/hooks/*.json` --
  installed by `pwsh ./install.ps1 -TargetRepo <r> -InstallAdapter copilot`.
  These fire deterministically (`sessionStart`, `sessionEnd`, `postToolUse`,
  `subagentStop`) and call the kit's PowerShell lifecycle scripts at
  `~/.agents/tools/`. Non-zero exits are logged-and-skipped on Copilot
  (NOT exit-2-blocking like Claude Code), so do NOT rely on hooks to
  abort tool calls; treat them as side-effect recorders.
- Custom agents (user + repo scope): `~/.copilot/agents/<name>.agent.md`
  and `<repo>/.github/agents/<name>.agent.md`. The kit installs both
  workflow-transport agents (workflow-explorer, workflow-implementer,
  workflow-reviewer, workflow-skeptic, workflow-ui-qa) and specialist
  agents (code-quality-reviewer, security-reviewer, modularity-expert,
  etc.) via the device-wide and per-repo install paths.
- User-defined slash commands: NOT supported by Copilot CLI (issue #1113).
  The kit's procedural workflow content lives inline in this file and in
  `~/.copilot/agentic-kit.md`.

When you (the agent) cannot find a hook firing, fall back to calling the
harness scripts directly from the workflow body -- the lifecycle calls
below remain valid even when hooks are missing.

## Core operating rules

1. Respect the `.kit` layout (`.kit/context/`, `.kit/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Default sequential. Swarms require parallel-safe verb + fan-out-able
   scope + explicit opt-in.

## Behavioral guardrails

- Do not assume missing details. Name uncertainty and ask when it changes the approach.
- Prefer the smallest change that solves the stated problem. Avoid speculative flexibility.
- Keep evidence separate from conclusions. Mark assumptions and unverified claims explicitly.
- For debugging, state the symptom before proposing causes. For analysis, surface tradeoffs instead of silently picking one.

## Startup repo preflight

At session start, check whether the current repo has the kit scaffold it needs:

- `.kit/context/memory.md`
- `.kit/workflows/`
- `.wiki/index.md`
- `.wiki/features.md`
- `.wiki/.features`

If `.kit` is missing, tell the user the repo is not bootstrapped for the kit yet and suggest one of:

- `/bootstrap-harness` (preferred when the host exposes repo commands)
- `pwsh <path-to-agentic-coding-kit>\scripts\install.ps1 -BootstrapHarness -TargetRepo "<repo>"`

If `.wiki/index.md`, `.wiki/architecture.md`, `.wiki/codebase.md`, `.wiki/features.md`, or `.wiki/.features` is missing, suggest:

- `/bootstrap-harness` if the repo is missing the full scaffold
- or the same installer bootstrap command above if the repo is missing the whole scaffold

`/bootstrap-harness` is the single high-level init path. It should scaffold the
repo AND run the evidence-based init flows (`git-archaeology`, `kit-init`,
`wiki-init`) so the repo is actually ready for coding afterward.

Do not pretend the repo is fully kit-enabled when these files are absent. Continue for quick questions if needed, but warn that memory routing, wiki updates, and repo-local workflow overrides will be incomplete until the scaffold exists.

## Verification freshness

If any file changes after verification was captured, rerun verification before claiming completion. Treat prior evidence as stale after later edits.

## Workflow source of truth

The **global workflow skills** under `~/.agents/skills/` are the canonical
workflow contract. This file exists to handle Copilot's host limitations
(especially no native hooks), not to redefine how `/build`, `/review`, or the
other workflows are supposed to behave.

If this file drifts from the global workflow skills, fix the source-of-truth
problem instead of layering more Copilot-specific exceptions.

## Lifecycle baked into every command

Even with hooks installed, every workflow command should explicitly call
the lifecycle scripts. **Do this without asking the user; it's the contract.**

### When the user says /build (or asks to implement, fix, refactor):

```
1. RUN: pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "<task>"
       Read the BRIEF block it emits. Note the SessionId, scope, tier,
       swarm mode, prior handoffs.

2. IF tierRec is INLINE: do the work in this turn, no sub-agents.
   IF TARGETED: spawn 1-3 reviewers via the workflow.
   IF FULL or SWARM: follow the full agent matrix from
   ~/.agents/skills/build/SKILL.md.

3. Implement only the scoped change. Mark gates as you complete them:
       pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "context_loaded"
       pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "implementation_done"
       (etc.)

4. Capture verification evidence (test output, build output) before claiming
   completion. Mark verification_evidence.

5. RUN: pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
       This auto-consolidates reflections and gates on accumulated backlog.
```

The build semantics themselves still come from `~/.agents/skills/build/SKILL.md`.
Copilot's custom-agent surface (.agent.md files) is now wired by the kit; subagents are spawnable. The workflow contract is the
same: respect the same phases, gates, memory routing, and read-stop discipline
instead of inventing a smaller Copilot-only build.

### When the user says /review, /plan, /analyze, /investigate, /refactor:

Same shape. Replace `-Mode build` with the matching mode. The lifecycle
calls are NOT optional -- they're how the kit's memory and self-improvement
loop survive across Copilot sessions.

### When the user just asks a quick question:

If the request is genuinely a single-turn answer (no code change), skip the
lifecycle. Lifecycle is for sessions that produce a handoff worth registering.

## Memory routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Role-specific guidance | `.kit/context/agent-memory/{role}.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session work | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` |

Before spawning a specialist role, run:

```
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId "<id>" -Role "<role>" -RepoRoot "<repo>"
```

If `found=true`, embed the returned `prompt_block` in the spawned role's
prompt. Do not skip this step -- it's how role memory works.

## Self-improvement loop

`post-session.ps1` runs `auto-consolidate.ps1` automatically. It:
- dedups identical reflection entries
- archives entries already promoted in `memory.md`
- drops stale single-occurrence entries (>30 days)
- auto-promotes additive patterns with 2+ occurrences

You usually don't need to run /reflect manually. Only when the gate exits 2
(>=5 unaddressed entries that need judgment) should you read the entries
and run the /reflect workflow.

## Important

If the user closes the terminal mid-session without you having called
post-session, the next pre-session invocation will detect the orphaned
session via session-meta.json and surface it as a prior handoff. Don't
panic; the kit is resilient. But the BEST behavior is to call post-session
at the natural end of every workflow turn that produced changes.
