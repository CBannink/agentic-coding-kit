---
name: bootstrap-harness
description: >
  Single high-level repo initialization. MUST BE USED when .kit/ or .wiki/ is
  missing OR the user says "set this repo up", "initialize the harness",
  "bootstrap this repo". Use PROACTIVELY on any first-time-in-repo session.
  Goal-conditioned: detects git/PR/architecture conventions, scaffolds .kit/ +
  .wiki/ + adapter files, runs kit-init + wiki-init + git-archaeology, writes a
  conventions.md the kit's other agents read. Iterates until every required
  outcome exists; surfaces any gap rather than claiming success early.
---

# Bootstrap Harness

`/bootstrap-harness` is the ONE high-level repo-init path. It is **goal-conditioned**: it does not stop until every required outcome below exists and has meaningful content. If something is missing after the first pass, it iterates (max 3 passes) before surfacing.

You ARE the orchestrator. Spawn `workflow-explorer`, `git-archaeology`, `kit-init`, `wiki-init` as needed; do NOT do the full setup inline.

## Required outcomes (the goal — every item must be checkable)

| File | Must contain |
|---|---|
| `.kit/context/memory.md` | Architecture facts grounded in real code; not template content |
| `.kit/context/handoffs.md` | Empty placeholder OR existing entries; structure valid |
| `.kit/context/history.md` | Architecture-decision log seeded from git-archaeology |
| `.kit/context/reflections.md` | Empty or seeded; structure valid |
| `.kit/context/conventions.md` | **NEW** — git workflow + PR review + architecture preferences (see Phase 1) |
| `.wiki/index.md` | TOC ≤100 lines listing all sections |
| `.wiki/architecture.md` | Boundaries + principles inferred from code |
| `.wiki/codebase.md` | Where important code lives; style conventions |
| `.wiki/features.md` | User-visible capabilities |
| `.wiki/.features` | Machine-readable feature index |
| `<host_root_for_repo>` adapter | `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md` per host |

## Workflow (goal-conditioned, iterates)

### Phase 0 — Resolve repo root + installer

Determine the repo root. Locate the installer (`scripts/install.ps1` from the kit's checked-out copy). Ask the user once if not known.

### Phase 1 — Detect repo conventions (runs BEFORE scaffold)

**Invoke the `git-archaeology` skill** (read `~/.agents/skills/git-archaeology/SKILL.md` and follow its full analysis sequence) to extract:

- Commit message style (conventional commits? imperative? scope tags?)
- New-file patterns (where things land, naming conventions)
- Hot files (high churn = fragile core or unstable area)
- Test file patterns (location, naming, framework)
- Change scope per commit (are tests always included?)
- Technology choices from recent diffs
- Error handling patterns
- Any reverts or repeated antipatterns

Then additionally detect the following **workflow conventions** not covered by git-archaeology:

**Git workflow conventions** — run these commands:
- Branch naming: `git branch -r | head -20` → detect `feat/`, `feature/`, `fix/`, `chore/` prefixes; release branches; trunk-based vs gitflow
- Merge strategy: `git log --merges -5 --oneline` + `git log -10 --pretty=format:'%H %s'` → merge commits present (merge strategy) or absent (squash/rebase)? `(#NNN)` PR-number suffixes = squash merges
- Commit style: `git log -50 --pretty=format:'%s'` → conventional-commits prefix? sentence-case? imperative? average subject length? granularity?
- PR templates: check `.github/pull_request_template.md` or `.github/PULL_REQUEST_TEMPLATE/`
- CODEOWNERS: check `.github/CODEOWNERS` or `CODEOWNERS`
- CI/CD config: `.github/workflows/*.yml` → which checks must pass before merge
- PR review density (if `gh` CLI available): `gh pr list --state merged --limit 20 --json author,reviews,title,additions,deletions`

**Architecture preferences** — code-driven evidence:
- Layering: `domain/`, `application/`, `infrastructure/`, `api/` dirs? Or `src/components/`, `src/lib/`, `src/server/`? Or flat?
- Dependency injection: check for `container.ts`/`container.py`; constructor params + factory functions
- Error handling: typed errors or string-based? Result/Either pattern?
- State management (frontend): Redux / Zustand / TanStack / context?
- API style: REST / GraphQL / tRPC / gRPC?
- Schema validation: Zod / Pydantic / Joi / none?
- Type system: TypeScript strict mode? mypy strict? `any` tolerated?

Combine the git-archaeology Project Conventions Profile with the workflow convention findings. Write **all** findings to `.kit/context/conventions.md`. Structure:

```markdown
# Repo Conventions (auto-detected by /bootstrap-harness)

## Git workflow
- Branch naming: <pattern>
- Merge strategy: <squash|merge|rebase>
- Commit style: <conventional|sentence|imperative|free-form>
- Commit granularity: <1-per-logical-change|WIP-then-squash|other>

## PR conventions
- Template: <yes:.github/pull_request_template.md | no>
- CODEOWNERS: <yes|no>
- Required checks: <list from CI config>
- Typical reviewer: <name or "any team member">
- Average PR size: <N lines>

## Architecture preferences
- Layering: <flat|MVC|layered (domain/application/infra)|other>
- DI: <container | constructor | direct instantiation>
- Error handling: <typed errors | strings | Result/Either>
- Tests: <framework + location convention>
- State (FE): <library>
- API: <REST | GraphQL | tRPC | other>
- Schema validation: <library | none>
- Type system: <strict | gradual | dynamic>

## Source
- Detected from: <commits sampled, files inspected>
- Generated by /bootstrap-harness on <date>
```

This file is read by other agents (`workflow-implementer`, `code-quality-reviewer`, `pr-reviewer`) so they implement / review per repo conventions, not generic best practices.

### Phase 2 — Scaffold the repo

Run:
```powershell
pwsh <path-to-agentic-coding-kit>\scripts\install.ps1 -BootstrapHarness -TargetRepo "<repo-root>"
```

This plants template files including a `.kit/context/conventions.md` placeholder. **Immediately after the scaffold completes, overwrite `.kit/context/conventions.md` with the real content detected in Phase 1.** The placeholder is a signal to run this step; replace it now.

Verify scaffold + adapter files exist before proceeding.

### Phase 3 — Initialize `.kit/` (spawn kit-init via Skill)

Read `~/.agents/skills/kit-init/SKILL.md` and execute the kit-init workflow. Pass the git-archaeology Project Conventions Profile and the `.kit/context/conventions.md` written in Phase 1 as grounding context, so `memory.md` reflects actual repo patterns rather than assumed ones.

### Phase 4 — Initialize `.wiki/` (spawn wiki-init via Skill)

Read `~/.agents/skills/wiki-init/SKILL.md` and execute the wiki-init workflow with conventions context. `wiki-init`'s `architecture.md` should reflect the detected layering, DI pattern, API style, etc. extracted in Phase 1.

### Phase 5 — Convergence check (goal gate, mechanical)

Bash-check every required outcome:

```bash
# All of these must exist AND be > 200 bytes (i.e., not empty placeholder)
for f in .kit/context/memory.md .kit/context/conventions.md \
         .wiki/index.md .wiki/architecture.md .wiki/codebase.md .wiki/features.md; do
  if [ ! -f "$f" ] || [ $(wc -c < "$f") -lt 200 ]; then
    echo "MISSING_OR_EMPTY: $f"
  fi
done
```

If anything reports `MISSING_OR_EMPTY`:
- Iteration ≤ 2: re-run only the failing phase (kit-init or wiki-init for the affected file).
- Iteration 3: surface to user with the specific gap.

### Phase 6 — Handoff (machine-parseable first line)

```
BOOTSTRAP_STATUS: <COMPLETE | PARTIAL | FAILED> | iterations: <N>/3 | conventions: <detected> | files: <count>
```

Then list:
- Detected git/PR/architecture conventions (one-line summary).
- Files written.
- Anything skipped (e.g., git-archaeology skipped because <20 commits).
- Recommended next step (typically "run /build to start coding — kit will read conventions.md and follow your patterns").

## Hard rules

1. Do not claim success just because install.ps1 ran.
2. Do not skip Phase 1 — convention detection is what makes downstream agents repo-aware. **Phase 1 MUST invoke `git-archaeology` (read and follow `~/.agents/skills/git-archaeology/SKILL.md`).** Without git-archaeology-backed conventions.md, the kit reverts to generic best practices and fights your repo's actual style.
3. Do not full-swarm by default — Phase 1 (3 parallel detection threads) is the only justified parallelism.
4. Every conventions claim must be backed by current code OR git history. State the evidence.
5. If iteration cap (3) is hit with anything still missing, surface — do NOT silently mark as complete.
