# Repo-Local Specialist Memory Protocol

Canonical rules for repo-specific agent memory.

## Location

Use this repo-local directory:

`.kit/context/agent-memory/`

Supported files:
- `shared.md`
- `{role}.md` keyed by the exact spawned role name, for example:
  - `implementer.md`
  - `spec-reviewer.md`
  - `security-reviewer.md`
  - `modularity-expert.md`
  - `qa-reviewer.md`
  - `ui-ux-expert.md`

## Loading

- Never auto-load this directory on session start.
- Load `shared.md` only when the spawned role needs repo-local specialist context that is not broad enough for `.kit/context/memory.md`.
- Load `{role}.md` only for the matching role.
- Pass only the relevant excerpt into the subagent prompt when possible.
- If the content is broad repo architecture, keep it in `memory.md` instead.

### Mechanical resolver (required when spawning a specialist role)

Before spawning a role that may need repo-local specialist memory, run:

`pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId "{session_id}" -Role "{role}" -RepoRoot "{repo-root}"`

The resolver:
- checks `shared.md` and `{role}.md`
- writes a session artifact under `${AGENTS_SESSION_ROOT}/{session_id}/resolved-specialist-memory/` (default `.kit/session-state/{session_id}/resolved-specialist-memory/` in a bootstrapped repo)
- records used files into `run-packet.json`
- records used files into `workflow-evidence.json`
- returns a `prompt_block` to embed directly into the spawned subagent prompt

If `found=false`, spawn normally with no repo-local specialist-memory injection.

## What belongs here

Write specialist memory only when the guidance is:
1. repo-specific
2. durable across sessions
3. role-targeted
4. more specific than repo memory, but more durable than a session handoff

Good examples:
- a security reviewer note about which middleware actually owns auth decisions in this repo
- an implementer note about a generator, registry, or container file that must always be updated together
- a QA note about artifact fixtures that silently drift from production output unless refreshed together
- a shared specialist note about how generated run artifacts are laid out and which samples are trustworthy

Bad examples:
- current task progress
- "what I tried"
- general repo architecture facts
- cross-repo workflow advice
- user-visible feature descriptions that belong in `.wiki/`

## Shared vs role-specific

Use `shared.md` when:
- 2 or more specialist roles need the same repo-local guidance
- the guidance is still too narrow for `.kit/context/memory.md`

Use `{role}.md` when:
- the rule is only relevant to one role
- loading it for other roles would mostly add noise

## Write threshold

Promote guidance here when you have either:
- repeated evidence in this repo across 2+ sessions, or
- one high-confidence repo-specific rule that would predictably save future specialist passes from known mistakes

If you are unsure, keep it in the private handoff instead.
