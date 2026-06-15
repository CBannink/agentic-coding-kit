# Memory and Session Model

## Core context classes

| Class | Location | Use for |
|---|---|---|
| Global workflow memory | `~/.agents/skills/{skill}/memory.md` | cross-repo workflow patterns |
| Repo memory | `.kit/context/memory.md` | durable facts about one repo |
| Repo context patterns | `.kit/context/patterns.md` | durable repo-specific agent guidance shared across roles |
| Legacy repo role memory | `.kit/context/agent-memory/` | read-only compatibility for old role-specific guidance |
| Session memory | `.kit/session-state/{SESSION_ID}/...` (default in a bootstrapped repo) | current task state and artifacts |

## Is build memory shared across repos?

Yes — **skill memory is intentionally cross-repo**. The build skill's
`~/.agents/skills/build/memory.md` is only for patterns that would still help in
a completely different repository.

That file should **not** contain:
- repo architecture facts
- repo-specific build commands
- project naming conventions
- one-off task notes

Route those instead to:
- `.kit/context/memory.md` for durable repo facts
- `.kit/context/patterns.md` for repo-specific agent guidance
- `.kit/context/agent-memory/{role}.md` only when legacy read-only compatibility requires role-specific guidance
- `.kit/session-state/{id}/...` for current-task notes

Normal reinstalls preserve accumulated skill memory, so the cross-repo pattern
bucket survives upgrades without leaking repo-specific facts into the wrong
place.

## Repo memory

`memory.md` is for:
- architecture facts
- verified commands
- constraints
- traps
- session handoff index

It is **not** for:
- current task progress
- speculative notes
- session chatter

## Repo context patterns

Use:

```text
.kit/context/
  patterns.md
```

This exists because some guidance is:
- too specific for `memory.md`
- too durable for a handoff
- worth sharing across roles without repeating it in every workflow brief

Hard cap: keep `patterns.md` under 200 lines. Repeated procedures should become
skills, workflow briefs, or tools instead of growing this file.

## Legacy repo role memory

Use `.kit/context/agent-memory/{role}.md` only when you need read-only
compatibility with older role-specific guidance. `specialist-memory-resolver.ps1`
excludes it by default and includes it only with `-IncludeLegacyRoleMemory`.

### Injection path

The mechanical path is:

```powershell
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 `
  -SessionId "{session_id}" `
  -Role "{role}" `
  -RepoRoot "{repo-root}"
```

Add `-IncludeLegacyRoleMemory` only when the task explicitly needs the old
read-only `agent-memory/` guidance. If `found=true`, inject the returned
`prompt_block`.

## Session artifacts

### `plan.md`
authoritative plan artifact for `/plan` and `/build`

### `run-packet.json`
compact reusable execution packet containing:
- plan summary
- approval state
- likely files
- integration points
- verification items
- repo context patterns used

### `workflow-evidence.json`
machine-readable proof of:
- tier
- scope
- repo context used
- agents spawned / skipped
- mode decisions
- verification commands
- write decisions

### `handoffs.md`
private full handoff body for the session

### `scratch.md`
work-in-progress findings, especially useful in long reviews

## Shared vs private handoffs

| File | Purpose |
|---|---|
| `.kit/context/handoffs.md` | shared session tag index only |
| `.kit/session-state/{id}/handoffs.md` | private full handoff body |

If `AGENTS_SESSION_ROOT` is set, kit-managed session artifacts follow that
override instead. Copilot's own host-native runtime under
`~/.copilot/session-state/` remains separate and is not controlled by this kit.

## Wiki memory

Use `.wiki/features.md` and `.wiki/.features` for:
- user-visible features
- public capabilities
- discovery docs

Do **not** bury this in repo memory.

That separation is important because:
- feature discovery changes differently from architecture memory
- it is consumed differently by planning and review workflows
