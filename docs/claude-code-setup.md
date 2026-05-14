# Claude Code Setup

## Goal

The kit supports Claude Code as a first-class host with full hook integration, agent auto-discovery, and slash command support.

What matters most is:
- the file layout
- the workflow prompts
- the memory model
- the session artifacts
- the lifecycle helper scripts

## What to keep the same

Keep these concepts unchanged:

| Concept | Keep it? |
|---|---|
| `.kit/context/*` repo memory model | **Yes** |
| `.wiki/features.md` + `.wiki/.features` | **Yes** |
| session-specific handoff body | **Yes** |
| run packet | **Yes** |
| review/build/plan workflow split | **Yes** |
| repo-local specialist memory | **Yes** |

## What Claude Code needs

Use the adapter files in:

```text
bundle/adapters/claude-code/
```

They provide:
- `CLAUDE.md`
- `.claude/commands/*.md`

These files document how to invoke:
- `/plan`
- `/build`
- `/review`
- `/analyze`
- `/investigate`

## Session namespace

This kit now defaults its **kit-managed** session artifacts to:

```text
<repo>/.kit/session-state/
```

If `AGENTS_SESSION_ROOT` is set, that override wins. Copilot's own native
runtime under `~/.copilot/session-state/` is separate and unaffected.

For Claude Code you have two options:

### Option A — easiest
Keep the namespace as-is.

This is the fastest path if you only care that it works.

### Option B — cleaner Claude branding
Rename it to:

```text
~/.claude/session-state/
```

If you do this, update path references in the installed skill/tool files.

## Commands in Claude Code

Claude Code now has **13 commands** installed (not just the basic 5 listed in older docs), plus **12 agents** including `goal-orchestrator` and `pr-reviewer`. Commands are auto-discovered from `.claude/commands/` — no manual registration needed.

If your Claude Code setup supports command markdown files under `.claude/commands`, copy the provided command files into the target repo.

If not, use the command files as **prompt templates** and keep `CLAUDE.md` as the main entrypoint.

### New tools available in Claude Code

`model-selector.ps1` and `agent-trust-scorer.ps1` are available via the `goal-orchestrator` agent for dynamic model selection. The orchestrator calls `model-selector.ps1` at task-start to pick the right model for a given scope + role, and `agent-trust-scorer.ps1` to inject calibration prompts when delegating to agents with a noisy track record.

## Recommended adoption path

1. install the global assets
2. bootstrap `.kit` and `.wiki` into a target repo
3. add the Claude adapter files to that repo
4. run the workflows with the same semantics as in this kit
5. keep the same memory routing rules

## What this kit is boasting about

The system is strong because it has:
- autonomous lite / targeted / full flow selection
- plan-first execution
- hierarchical review swarms
- repo-local specialist memory
- hook-ready lifecycle helpers
- compact run packets for resuming and compaction
- wiki-aware feature memory
- explicit write-routing and verification discipline

That combination is rare. Most setups have fragments of it, not the full stack.
