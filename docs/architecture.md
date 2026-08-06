# Architecture

Agentic Coding Kit is a portable engineering control layer for Codex, Claude
Code, OpenCode, and GitHub Copilot CLI. The harness supplies the agent runtime,
tools, permissions, context window, and native subagents. ACK supplies concise
operating policy, progressively loaded procedures, specialist judgment, safe
installation, and repository knowledge.

## Runtime model

The active host session is the only primary orchestrator. It owns the user's
goal, acceptance criteria, plan, context, integration, proof, and final answer.
ACK has two adaptive modes:

```text
INLINE: Minimal task with bounded context present before routing -> Change or answer -> Verify -> Stop

LOOP:   Anchor -> Partition -> Dispatch -> Integrate/Verify -> fresh Reviewer
                         ^                                   |
                         +---------- fresh repair -----------+
```

LOOP is a dynamic execution map, not a TypeScript workflow engine. One
production writer is the default; up to three Coders may run when contracts are
fixed and write sets are disjoint. Every specialist invocation is terminal;
repair and re-review use fresh contexts. Subagents
return compact `Result`, `Evidence`, and optional `Next` packets and never
dispatch successors.

## Product layers

| Layer | Location | Owns |
|---|---|---|
| Canonical product | `core/` | Orchestrator, skills, agents, manifest, schemas |
| Optional capability packs | `packs/` | Browser QA and UI critique |
| Management implementation | `cli/src/` | Validation, rendering, installation, wiki, safety |
| Generated host adapters | `adapters/` | Checked-in renderer output; never edit as source |
| Repository knowledge | `.wiki/` | Explicitly generated, source-backed navigation and conventions |

The canonical-to-host flow is:

```text
core/manifest.yaml + canonical prompts
-> schema and semantic validation
-> deterministic rendering
-> adapters/<host>
-> conflict-aware native installation
-> ownership manifest for update and uninstall
```

OpenCode receives the canonical orchestrator in a managed `mode: primary`
agent because its built-in Build primary is not the desired ACK experience.
Codex receives the same policy through root `developer_instructions` in its
native configuration. ACK does not put either policy in `AGENTS.md`, because
that repository instruction surface is inherited by specialists. Claude and
Copilot use their native managed instruction files.

Specialists receive their small role prompt plus a pointer-based Assignment:
goal, acceptance criteria, plan, exact paths, and compact facts that cannot be
recovered from those paths. They do not receive pasted source, diffs, wiki
pages, logs, transcripts, or complete prior returns. Codex specialist configs
disable nested agents and ACK skills; OpenCode specialist permissions deny
skills and task dispatch.

## Skills and agents

Skills own procedures: Build, Design, Architecture, Grill, Analyze, Review, PR
Ready, Threat Model, Wiki, and Experiment. They load only when useful. Agents
own bounded fresh contexts or distinct permissions: Architect, Scout, Coder,
Reviewer, Test Engineer, Diagnostician, Sage, and Security Reviewer. Browser QA
and UI Critic are optional.

The kit deliberately has no nested orchestrator, session-state runtime,
reflection store, goal daemon, graph database, or persistent task DAG. The
useful graph concept is the primary's compact execution map; the useful
repository graph is a future measurable retrieval experiment, not a core
dependency.

## Evidence and state

The primary keeps only active in-context state: goal, decisions, changed paths,
evidence, findings, and failure signatures. Fresh source and executable checks
remain authoritative. `.wiki` is repository navigation, not task memory.

Deterministic tooling enforces prompt budgets, model neutrality, path
containment, managed ownership, adapter drift, evidence freshness, and
recoverable installation. Prompt policy guides judgment; it does not pretend to
mechanically guarantee model behavior.
