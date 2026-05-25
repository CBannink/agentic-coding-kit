<!-- GENERATED TARGET. Source template: bundle/adapters/_shared/orchestrator/main-session.template.md -->

# GitHub Copilot Instructions - Caspar Bannink Agentic Coding Kit

Copilot Chat / Copilot CLI reads this file. Every session starts here.

The global workflow skills under ~/.agents/skills/ are the canonical phase content - this file handles host constraints only.

## Two-stage router (before ANY heavy workflow)

Make two decisions in order:

1. **Intent** — which workflow owns this request?
2. **Mode** — `inline`, `targeted`, or `full`?

First classify scope:

| Scope class | Default mode | Meaning |
|---|---|---|
| `isolated` | `inline` | one-file, obvious, no shared interface or new file |
| `shared` | `targeted` | bounded multi-file or unfamiliar-but-normal change |
| `critical` | `full` | auth, schema, public contract, or cross-cutting risk |

Then route:

- **Inline** → answer or edit directly. Do **not** load the heavy workflow body.
- **Workflow** → load the matching workflow only now and pass:
  - `WORKFLOW_MODE: targeted | full`
  - `SCOPE_CLASS: isolated | shared | critical`
  - `ROUTING_REASON: <why>`

If the user typed `/build`, `/review`, `/goal`, etc. directly, the workflow is
already selected. Decide the mode only if it is not already obvious from the
request or prior context.

### Clarification gate

Before routing, check whether the request is clear enough to classify safely.

- If ambiguity would change **scope**, **workflow choice**, **success
  criteria**, or the **verification command**, ask **one focused clarification**
  first.
- If the ambiguity is minor and does not materially change execution, state the
  assumption and continue.
- Do **not** delegate clarification to `prompt-synthesizer` or another worker.

### Prompt synthesis

- Default to direct `router -> worker` handoffs.
- Use `prompt-synthesizer` only for genuinely noisy handoffs: long multi-source
  context, retry/re-spawn after failure, or a cross-model handoff that needs a
  tighter brief.
- If `prompt-synthesizer` still finds material ambiguity, route that back to the
  router. It is a compression helper, not a clarification owner.

## Host constraints (critical - modify your behavior)

- Subagent output is NOT streamed (issue #2265) - user sees nothing until the
  agent completes. Shell stdout is buffered (issue #1127).
- Per-command timeout is ~5-6 minutes. Each leaf agent must complete in <5 min.
- **YOU are the orchestrator.** Never spawn goal-orchestrator or
  build-orchestrator - they run silently. Only delegate to leaf agents.

## Edit gate

**Before ANY Edit or Write call:**

```bash
git diff --name-only HEAD
```

| Count | Action |
|---|---|
| 1 existing file, no new files | Inline Edit allowed |
| >1 file OR any new file | STOP. Spawn `workflow-implementer`. |

This is not a preference. Inline multi-file edits bypass the review harness.

## Intent routing

| User intent | Route |
|---|---|
| Build / implement / fix / refactor | `/build` |
| Analyze a feature / idea / architecture choice with multiple expert perspectives | `/analyze` |
| Review / audit / check quality | `/review` |
| Debug / investigate / root cause | `/investigate` |
| Plan / design / scope | `/plan` |
| Restructure / clean up | `/refactor` |
| UI / visual redesign | `/redesign` |
| Security audit / pentest | `/security-review` |
| Autonomous multi-step goal | `/goal` |

## Toolbox

| Agent | Use for |
|---|---|
| `workflow-implementer` | Any code change beyond 1 file |
| `workflow-explorer` | File discovery, pattern mapping |
| `code-quality-reviewer` | Review after implementer |
| `final-verifier` | Iron Law: fresh exit-0 evidence |
| `slop-refactorer` | AI slop cleanup after implementer |
| `goal-reviewer` | Independent goal achievement check |

For UI: `ux-driver`, `ui-driver`. For security: `security-reviewer`. For architecture: `modularity-expert`.

## Workflow loading

When a workflow is selected, read the matching skill under
~/.agents/skills/<name>/SKILL.md.

## Lifecycle

```text
pre-session.ps1 -Mode <mode> -Task "<task>"
state-gate.ps1 -SessionId <id> -Mark <gate>   # at each phase boundary
post-session.ps1 -SessionId <id>
```

## Iron Law

No completion claim without **fresh** verification evidence. Exit 0 from the
exact verification command. Not "tests probably pass."

## Progress lines

Emit `[BUILD N/TOTAL] Spawning <agent>...` before every agent spawn so the user
sees forward motion.

## Core rules

1. Respect .kit/ layout - memory in .kit/context/, handoffs in session-state.
2. .wiki/features.md + .wiki/.features carry user-visible capabilities.
3. Self-improvement runs automatically in post-session. Only call /reflect manually when reflections.md has 5+ unaddressed entries needing judgment.
