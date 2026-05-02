# File Layout

## Global home-level files

Install these under your home directory.

```text
~/
  .agents/
    skills/
    tools/
    context/
  .codex/
    global-workflows/
      plugins/
```

### `~/.agents/skills/`

Contains reusable workflow skills such as:
- `plan`
- `build`
- `review`
- `analyze`
- `investigate`
- `refactor`
- `spec`
- `tdd`
- `verification-loop`
- `consequence`
- `reflect`

Also includes expert skills and supporting skills:
- `experts/modularity`
- `experts/ui-ux`
- `experts/performance`
- `experts/silent-failure-hunter`
- `gstack-*`
- `git-archaeology`
- `derive-repo-skills`

### `~/.agents/tools/`

Operational scripts:
- `pre-session.ps1`
- `post-session.ps1`
- `scope-classifier.ps1`
- `state-init.ps1`
- `state-gate.ps1`
- `handoff-register.ps1`
- `brief-resolver.ps1`
- `workflow-evidence.ps1`
- `run-packet.ps1`
- lifecycle helper scripts
- `specialist-memory-resolver.ps1`

### `~/.agents/context/`

Protocol files:
- `writeback-protocol.md`
- `reflection-protocol.md`
- `repo-specialist-memory-protocol.md`
- `workflow-evidence-protocol.md`
- `skill-memory-index.json`

## Repo-local files

These live inside each target repo.

```text
.codex/
  context/
    memory.md
    history.md
    handoffs.md
    reflections.md
    agent-memory/
      shared.md
      {role}.md
  workflows/
    shared.md
    analyze.md
    build.md
    review.md
    investigate.md
```

### What each file is for

| File | Purpose |
|---|---|
| `memory.md` | durable repo facts + session handoff index |
| `history.md` | major milestones, bugs fixed, architectural decisions |
| `handoffs.md` | shared session tag index only |
| `reflections.md` | unaddressed workflow improvement candidates |
| `agent-memory/shared.md` | repo-local role guidance shared by multiple specialists |
| `agent-memory/{role}.md` | repo-local role-specific guidance |

## Wiki files

```text
.wiki/
  features.md
  .features
```

Use these for **user-visible capability memory**, not general repo memory.

## Session artifacts

```text
~/.copilot/session-state/{SESSION_ID}/
  plan.md
  handoffs.md
  scratch.md
  workflow-evidence.json
  state.json
  run-packet.json
  compact-brief.md
  subagent-events.jsonl
  hook-events.jsonl
  resolved-specialist-memory/
```

If you want a Claude Code-native namespace, change this to:

```text
~/.claude/session-state/{SESSION_ID}/
```

The docs and adapters explain that migration.
