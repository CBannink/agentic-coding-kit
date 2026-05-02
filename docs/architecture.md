# Architecture

## Core idea

This system is a **workflow operating layer** for coding agents.

It combines:
1. global workflow skills
2. repo-local context and memory
3. session-private artifacts
4. hook-ready lifecycle helpers
5. explicit verification gates

The result is a system that can be:
- lightweight on small changes
- aggressive on risky changes
- consistent across sessions

## Layers

| Layer | Location | Purpose |
|---|---|---|
| Global workflow logic | `~/.agents\skills\` | reusable workflow behavior across repos |
| Global helper scripts | `~/.agents\tools\` | state init, evidence capture, run packet, lifecycle helpers |
| Global protocols | `~/.agents\context\` | writeback, reflection, repo-specialist-memory, evidence schemas |
| Global plugin layer | `~/.codex\global-workflows\plugins\` | gstack / superpowers / extended prompts |
| Repo-local context | `.codex\context\` | durable repo memory, history, handoffs, reflections |
| Repo-local workflow overrides | `.codex\workflows\` | repo-specific constraints or additions |
| Repo-local docs/wiki | `.wiki\` | user-visible feature catalog and machine manifest |
| Session artifacts | `~/.copilot\session-state\{SESSION_ID}\` | plan, handoff body, workflow evidence, run packet, hook events |

## Why the split matters

### Global
Use global files for things that should help in many repos:
- workflow structure
- tool scripts
- universal coding/review patterns

### Repo-local
Use repo-local files for things that only make sense inside one codebase:
- architecture facts
- feature catalogs
- conventions
- handoff indexes
- role-specific repo memory

### Session-private
Use session artifacts for:
- current task state
- scratch findings
- compact recovery packets
- workflow evidence

That separation is what prevents memory pollution.

## Lifecycle helpers

These scripts are **hook-ready**, meaning they can be called:
- by a harness
- by explicit workflow steps
- by a future host callback system

| Script | Purpose |
|---|---|
| `session-start-hook.ps1` | session start event |
| `precompact-hook.ps1` | compact-friendly snapshot before context pressure |
| `subagent-stop-hook.ps1` | normalize subagent result events |
| `session-end-hook.ps1` | session close snapshot |
| `run-packet.ps1` | maintain compact execution packet |
| `specialist-memory-resolver.ps1` | resolve repo-local role memory into injectable prompt text |

## What makes it strong

This stack is not just "many agents".

It is:
- **plan-first**
- **verification-first**
- **memory-routed**
- **session-aware**
- **hierarchically reviewed**

That combination matters more than raw swarm size.
