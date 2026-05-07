---
name: bootstrap-harness
description: >
  Single high-level repo initialization workflow. Bootstraps the scaffold, runs
  git-archaeology when history is sufficient, then drives kit-init and wiki-init
  so the repo is actually ready for coding. Use when .kit/.wiki are missing,
  architecture/codebase docs are absent, or the user asks to set up a repo for
  the harness in one step.
---

# Bootstrap Harness

`/bootstrap-harness` is the ONE high-level repo-init path.

Do not stop at "the files exist now". The workflow is only complete when the
repo is both:

1. **structurally scaffolded**
2. **semantically initialized** with repo memory, architecture docs, codebase
   conventions, and feature docs grounded in real code (and git history when
   available)

## What this workflow owns

- repo scaffold install (`.kit/`, `.wiki/`, repo adapter files)
- git-backed conventions discovery (`git-archaeology`)
- durable repo memory init (`kit-init`)
- wiki + architecture + codebase docs init (`wiki-init`)

It replaces telling the user to run those as separate setup steps.

## When to use

- `.kit/` is missing
- `.wiki/` is missing
- `.wiki/index.md`, `.wiki/architecture.md`, or `.wiki/codebase.md` is missing
- repo adapter files are missing
- user says "set this repo up correctly", "initialize the harness", "bootstrap this repo"

## When not to use

- the repo is already initialized and the user wants a focused refresh of only
  `.kit` or only `.wiki`
- the user explicitly asked for `/kit-init` or `/wiki-init` only

## Default execution model

**Sequential overall.**

Do NOT use full swarm by default. This workflow has cross-step dependencies:
install -> archaeology -> memory/wiki synthesis -> writeback.

### Allowed parallelism

Use light parallel exploration only when it reduces manual excavation:

1. one thread/agent for git history conventions (`git-archaeology`)
2. one thread/agent for `.kit`-oriented durable facts
3. one thread/agent for `.wiki` section/codebase/feature mapping

Then synthesize once and write once. That is **targeted parallelism**, not
full swarm-fanout.

Full swarm is justified only for very large repos where section discovery is
naturally independent by module/package.

## Required outcome

After `/bootstrap-harness`, these should exist and be meaningful:

- `.kit/context/memory.md`
- `.kit/context/handoffs.md`
- `.kit/context/history.md`
- `.kit/context/reflections.md`
- optional `.kit/context/agent-memory/shared.md`
- optional `.kit/workflows/{shared,build,review}.md`
- `.wiki/index.md`
- `.wiki/architecture.md`
- `.wiki/codebase.md`
- `.wiki/features.md`
- `.wiki/.features`
- repo adapter files appropriate for the host (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`)

## Workflow

### Step 1 — Resolve repo root and installer path

Determine the repo root from the current workspace.

If the local `agentic-coding-kit` repo path is known, use it.
If it is not known, ask the user for it once.

### Step 2 — Scaffold the repo

Run:

```powershell
pwsh <path-to-agentic-coding-kit>\scripts\install.ps1 -BootstrapHarness -TargetRepo "<repo-root>"
```

Verify that the scaffold and adapter files now exist.

### Step 3 — Decide archaeology depth

If the repo has enough history (roughly 20+ commits), run `git-archaeology`.
If not, explicitly note that conventions will come from current code only.

### Step 4 — Gather evidence

Use the minimum coordination needed:

- `git-archaeology` for conventions
- `kit-init` evidence gathering for durable repo facts
- `wiki-init` evidence gathering for architecture, codebase map, sections, and features

Parallelize only the exploration if it is truly independent. The final write
decisions must be synthesized coherently.

### Step 5 — Initialize `.kit`

Run the `kit-init` workflow so repo memory is grounded in:

- stable architecture facts
- repo-local workflow constraints
- cross-role coding conventions when warranted

### Step 6 — Initialize `.wiki`

Run the `wiki-init` workflow so the wiki contains:

- `index.md` as the entry point
- `architecture.md` for boundaries and architecture principles
- `codebase.md` for where important code lives and coding style norms
- `features.md` / `.features` for user-visible capabilities

### Step 7 — Verify the repo is actually coding-ready

Confirm that:

- the scaffold exists
- `.wiki/architecture.md` and `.wiki/codebase.md` exist
- `wiki-resolver.ps1` would have cross-cutting docs to load
- `.kit/context/memory.md` exists and is not just absent or skipped

If any of those are missing, `/bootstrap-harness` is not done yet.

## Hard rules

1. Do not claim success just because install.ps1 ran.
2. Do not bounce the user to `/kit-init` or `/wiki-init` as "next steps" in the
   normal bootstrap path — run them as part of this workflow.
3. Do not full-swarm by default. Prefer targeted parallel evidence gathering.
4. Keep docs small enough to be loaded during coding.
5. Every conventions claim must be backed by current code or git history.

