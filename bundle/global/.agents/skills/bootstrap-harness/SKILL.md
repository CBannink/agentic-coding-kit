---
name: bootstrap-harness
description: Single high-level repo initialization. MUST BE USED when .kit/ or .wiki/ is missing OR the user says "set this repo up", "initialize the harness", "bootstrap this repo". Use PROACTIVELY on any first-time-in-repo session. Goal-conditioned: detects git/PR/architecture conventions, scaffolds .kit/ + .wiki/ + adapter files, runs kit-init + wiki-init + git-archaeology, writes a conventions.md the kit's other agents read. Iterates until every required outcome exists; surfaces any gap rather than claiming success early.
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

### Phase 1 — Detect repo conventions (NEW, runs BEFORE scaffold)

Spawn `workflow-explorer` (or do inline for small repos) to detect:

**Git workflow conventions** — Bash-driven evidence:
- Branch naming pattern: `git branch -r | head -20` → look for `feat/`, `feature/`, `fix/`, `chore/` prefixes; release branches; trunk-based vs gitflow
- Merge strategy: `git log --merges -5 --oneline` → are merge commits present (merge strategy) or absent (squash/rebase)? `git log -10 --pretty=format:'%H %s'` → look for `(#NNN)` PR-number suffixes typical of squash merges
- Commit cadence + style: `git log -50 --pretty=format:'%s'` → conventional-commits prefix (`feat:`, `fix:`, `refactor:`)? Sentence-case? Imperative mood? Average subject length? How granular (1 logical change per commit vs WIP commits)?
- PR templates: check `.github/pull_request_template.md` or `.github/PULL_REQUEST_TEMPLATE/`
- CODEOWNERS: check `.github/CODEOWNERS` or `CODEOWNERS`
- CI/CD config: `.github/workflows/*.yml` → which checks must pass before merge

**Architecture preferences** — code-driven evidence:
- Layering: are there `domain/`, `application/`, `infrastructure/`, `api/` dirs? Or `src/components/`, `src/lib/`, `src/server/` (Next/React)? Or flat? Capture the layout.
- Dependency injection: grep for constructor params + factory functions; check for a `container.ts`/`container.py`. If present, note "constructor DI via container"; if absent, note "direct instantiation OK".
- Error handling: typed errors (custom `Error` subclasses) or string-based? Result/Either pattern?
- Test framework + location: `pytest` / `jest` / `vitest` / `cargo test` etc. + `tests/` vs `__tests__/` vs co-located.
- State management (frontend): Redux / Zustand / TanStack / context? Capture.
- API style: REST / GraphQL / tRPC / gRPC?
- Schema validation: Zod / Pydantic / Joi / none?
- Type system: TypeScript strict mode? mypy strict? `any` usage tolerated?

**PR review preferences** — git-archaeology-driven evidence:
- `git log -30 --merges` to see what merge commits look like; extract reviewer attribution if `Reviewed-by:` trailers present
- Look at recent closed PRs (if `gh` CLI available): `gh pr list --state merged --limit 20 --json author,reviews,title,additions,deletions` → average PR size, average review-comment density, who tends to review

Write all findings to `.kit/context/conventions.md`. Structure:

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

Verify scaffold + adapter files exist before proceeding.

### Phase 3 — Initialize `.kit/` (spawn kit-init via Skill)

Use the Skill tool to invoke `kit-init`. Pass the conventions.md from Phase 1 as context so kit-init's memory.md is grounded in detected patterns, not assumed ones.

### Phase 4 — Initialize `.wiki/` (spawn wiki-init via Skill)

Same — Skill invocation with conventions context. wiki-init's `architecture.md` should reflect the detected layering, DI pattern, etc.

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
2. Do not skip Phase 1 — convention detection is what makes downstream agents repo-aware. Without conventions.md, the kit reverts to generic best practices and fights your repo's actual style.
3. Do not full-swarm by default — Phase 1 (3 parallel detection threads) is the only justified parallelism.
4. Every conventions claim must be backed by current code OR git history. State the evidence.
5. If iteration cap (3) is hit with anything still missing, surface — do NOT silently mark as complete.
