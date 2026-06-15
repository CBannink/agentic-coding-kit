# Team Demo Guide

Use this when you want to show the kit in **10-15 minutes** without drowning the
team in internals.

## Demo goal

Show that the kit gives you one operating model across hosts, while **Copilot
CLI is the easiest practical demo path right now**.

## Suggested flow

### 1. Open with the framing (1 min)

Say:

> "This is not one more prompt file. It is a harness: shared workflows,
> lifecycle hooks, memory routing, repo bootstrap, and verification discipline."

### 2. Show the install surface (2 min)

Run:

```powershell
pwsh ./scripts/install-copilot.ps1
pwsh ./scripts/doctor.ps1
```

Explain:
- `~/.agents/` is the shared brain
- Copilot gets thin wrappers and agent files
- Claude/OpenCode can use the same underlying kit later

### 3. Show repo bootstrap (3 min)

Run:

```powershell
$demoRepo = Join-Path $env:TEMP "agentic-kit-demo"
New-Item -ItemType Directory -Path $demoRepo -Force | Out-Null
pwsh ./scripts/install-copilot.ps1 -BootstrapHarness -TargetRepo $demoRepo
```

Then explain what appears:
- `.kit/` for repo memory + workflow state
- `.wiki/` for user-visible capabilities
- repo adapter files for the host

### 4. Show a Copilot workflow wrapper (3 min)

Use a safe request, for example:

```powershell
pwsh (Join-Path $demoRepo ".github\copilot-bin\kit-review.ps1") "review this sample repo and call out the safest next improvement"
```

What to point out:
- live phase logging
- named subagents
- repo-local session artifacts
- the harness coordinates, not just the prompt

### 5. Close with the architecture point (2 min)

Say:

> "Claude Code has the richest native surface, but the kit keeps the workflow
> contract stable. Copilot needs more wrapper help, so we optimize that path
> explicitly without forking the whole design."

## Questions you will likely get

### "Is memory shared across repos?"

Answer:

> "Only the skill-pattern bucket is shared, and that is intentionally limited to
> universal workflow patterns. Repo facts stay in `.kit/context/memory.md`."

### "Why not just use Claude?"

Answer:

> "Claude is stronger on native workflow ergonomics. Copilot is worth supporting
> because many teams already have it, so this kit gives them a disciplined path
> without changing the repo model."

## Best demo artifacts to leave behind

- this repo's `README.md`
- `docs/setup-and-install.md`
- `docs/memory-and-session-model.md`
