# Memory and Session Model

## Four memory classes

| Class | Location | Use for |
|---|---|---|
| Global workflow memory | `~/.agents/skills/{skill}/memory.md` | cross-repo workflow patterns |
| Repo memory | `.codex/context/memory.md` | durable facts about one repo |
| Repo specialist memory | `.codex/context/agent-memory/` | durable role-specific guidance for one repo |
| Session memory | `~/.copilot/session-state/{SESSION_ID}/...` | current task state and artifacts |

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

## Repo specialist memory

Use:

```text
.codex/context/agent-memory/
  shared.md
  implementer.md
  security-reviewer.md
  ...
```

This exists because some guidance is:
- too specific for repo memory
- too durable for a handoff
- useful only for a particular role

### Injection path

The mechanical path is:

```powershell
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 `
  -SessionId "{session_id}" `
  -Role "{role}" `
  -RepoRoot "{repo-root}"
```

If `found=true`, inject the returned `prompt_block`.

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
- repo specialist memory used

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
| `.codex/context/handoffs.md` | shared session tag index only |
| `~/.copilot/session-state/{id}/handoffs.md` | private full handoff body |

## Wiki memory

Use `.wiki/features.md` and `.wiki/.features` for:
- user-visible features
- public capabilities
- discovery docs

Do **not** bury this in repo memory.

That separation is important because:
- feature discovery changes differently from architecture memory
- it is consumed differently by planning and review workflows
