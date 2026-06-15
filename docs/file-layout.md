# File Layout

## Global home-level files

Install these under your home directory.

```text
~/
  .agents/
    skills/
    tools/
    context/
    workflows/
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
- `test-strategy`
- `silent-failure-hunter`
- `verification-before-completion`
- `skill-import`
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
- `agent-trust-scorer.ps1`
- `scope-classifier.ps1`
- `reflection-emitter-stats.ps1`

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
.kit/
  context/
    patterns.md
    conventions.md
    workflow-briefs/
      workflow-explorer.md
      workflow-implementer.md
      workflow-ui-qa.md
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
| `patterns.md` | default repo-specific agent guidance shared across roles |
| `conventions.md` | compact repo conventions discovered during bootstrap |
| `workflow-briefs/*.md` | small role-specific briefs for the lean workflow agents |

Legacy `memory.md`, `history.md`, `handoffs.md`, `reflections.md`, and
`agent-memory/` files may exist in older repos. They are opt-in compatibility
context, not default startup context.

## Wiki files

```text
.wiki/
  features.md
  .features
```

Use these for **user-visible capability memory**, not general repo memory.

## Session artifacts

```text
.kit/session-state/{SESSION_ID}/
  plan.md
  handoffs.md
  scratch.md
  workflow-evidence.json
  state.json
  run-packet.json
  compact-brief.md
  subagent-events.jsonl

# Or `${AGENTS_SESSION_ROOT}/{SESSION_ID}/...` if explicitly overridden.
  hook-events.jsonl
  resolved-specialist-memory/
```

If you want a Claude Code-native namespace, change this to:

```text
~/.claude/session-state/{SESSION_ID}/
```

The docs and adapters explain that migration.
