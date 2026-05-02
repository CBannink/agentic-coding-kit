# GitHub Copilot Instructions -- Caspar Bannink Agentic Coding Kit

Copilot Chat / Copilot CLI reads this file. **Copilot has no native session
lifecycle hooks**, so the lifecycle calls below are baked into the workflow
itself: when the user invokes /build, /review, /plan, etc., YOU (the agent)
call the harness scripts directly. This is the only path to keep the
self-improvement loop closed under Copilot.

## Core operating rules

1. Respect the `.codex` layout (`.codex/context/`, `.codex/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Default sequential. Swarms require parallel-safe verb + fan-out-able
   scope + explicit opt-in.

## Lifecycle baked into every command

Because Copilot has no hooks, every workflow command must explicitly call
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
| Durable repo facts | `.codex/context/memory.md` |
| Role-specific guidance | `.codex/context/agent-memory/{role}.md` |
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
