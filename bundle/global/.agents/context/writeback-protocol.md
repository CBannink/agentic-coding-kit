# Shared Writeback Protocol

Canonical writeback rules for all workflow modes.

## Routing

Classify each observation into exactly one bucket:

| Bucket | Write to | Use when |
|---|---|---|
| `REPO-FACT` | `.kit/context/memory.md` | Durable repo architecture, verified commands, schema decisions, constraints |
| `REPO-SPECIALIST` | `.kit/context/agent-memory/shared.md` or `.kit/context/agent-memory/{role}.md` | Durable repo-local guidance that is only useful to one specialist role or a small set of specialist roles |
| `SKILL-PATTERN` | `~/.agents/skills/{skill}/memory.md` | Cross-repo workflow/build/review/analyze/investigate pattern with recurring evidence or one high-confidence universal pattern |
| `SESSION-ONLY` | `~/.agents/session-state/{session_id}/handoffs.md` or `scratch.md` | Task progress, one-off notes, speculative ideas, unresolved local context |

If classification is unclear, keep it `SESSION-ONLY`.

## Repo-specialist memory

Canonical layout:

` .kit/context/agent-memory/ `

- `shared.md` — repo-local specialist guidance shared by multiple roles
- `{role}.md` — repo-local guidance for one exact role name

Write here only when all of the following are true:
1. the guidance is repo-specific
2. it is durable across sessions
3. it is not general enough for `.kit/context/memory.md`
4. it is not just current-task chatter

Examples:
- security-reviewer-only trust-boundary traps
- implementer-only file ownership gotchas
- shared specialist rules about generated artifacts, DI wiring, or fixture layout

Do **not** put these here:
- user-visible feature descriptions → `.wiki/features.md` / `.wiki/.features`
- general repo architecture facts → `.kit/context/memory.md`
- cross-repo workflow patterns → `~/.agents/skills/{skill}/memory.md`
- current task progress → private handoff or scratch

Canonical details:

`~/.agents/context/repo-specialist-memory-protocol.md`

## Canonical registration

`post-session.ps1` is the single owner of:
1. private handoff body
2. shared `handoffs.md` tag line
3. machine-readable `handoffs.index.jsonl`
4. `memory.md` Session Handoff Index row
5. ingestion of `workflow-evidence.json` into the handoff and JSONL index when present

Skills should write the private handoff body only. They should not append shared tags manually.

## Workflow evidence sidecar

Optional but preferred session-proof file:

`~/.agents/session-state/{session_id}/workflow-evidence.json`

Capture it using:

`pwsh ~/.agents/tools/workflow-evidence.ps1`

Canonical schema and event examples live in:

`~/.agents/context/workflow-evidence-protocol.md`

## Run packet sidecar

Compact session contract:

`~/.agents/session-state/{session_id}/run-packet.json`

Use it to carry the minimum reusable session state between `/plan`, `/build`, hook helpers, and specialists:
- plan summary
- approval state
- likely files
- integration points
- verification expectations
- specialist-memory files used

Maintain it with:

`pwsh ~/.agents/tools/run-packet.ps1`

## Build Brief schema

Use this section in the private handoff when a prior session should feed `/build`:

```md
## Build Brief [YYYY-MM-DD]
- Source: analyze|investigate
- Objective: [what /build should implement]
- Affected files: [exact paths]
- Known blast radius: [summary or "not traced"]
- Constraints: [list]
- Modules already mapped: [list]
- Next steps: [ordered list]
```

Legacy headers remain readable for backward compatibility:
- `## Analysis-to-Build Brief [YYYY-MM-DD]`
- `## Investigation-to-Build Brief [YYYY-MM-DD]`

## Shared handoff tag schema

Shared tags are single-line records:

```md
## [SESSION: {id} | Task: {task} | Mode: /{mode} | Status: complete|in-progress | Outcome: {outcome} | Keywords: {csv} | Files: {csv} | Handoff: {absolute-path}]
```

Preferred fields for retrieval:
- `Mode`
- `Outcome`
- `Keywords`
- `Files`

## Numeric baseline rule

Any test/build/error-rate baseline written to memory must include:

```md
[verified: YYYY-MM-DD, sha: SHORT_SHA]
```
