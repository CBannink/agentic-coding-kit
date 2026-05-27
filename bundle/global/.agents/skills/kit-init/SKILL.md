---
name: kit-init
description: Use when .kit/ is missing or repo memory needs setup. Creates compact repo facts, conventions, workflow briefs, and agent memory from code evidence.
---

# Kit Init Skill

Bootstrap the `.kit/` directory from REAL code evidence in this repo.
Parallel to `/wiki-init` -- but for the kit's runtime memory artifacts
(durable repo facts, repo-local workflow overrides, agent-memory) instead
of the user-visible wiki.

## When to run

- `.kit/` does not exist in the repo
- `pre-session.ps1` emitted `KIT: MISSING` in the BRIEF block
- `/build` / `/review` / `/plan` skills report "memory.md not found" or
  silently skip their context-load step
- User asks to "bootstrap the kit's repo memory", "set up `.kit/`",
  "init the repo for the agentic kit"

## What this skill does NOT do

- It does NOT generate `.kit/skills/index.json` or `.kit/skills/profile.md`.
  Those are the output of the separate `derive-repo-skills` workflow. Run
  `/derive-repo-skills` (or the underlying skill) AFTER `/kit-init` if you
  want repo-local skill routing.
- It does NOT touch `.wiki/` -- run `/wiki-init` for that surface.
- It does NOT auto-create per-role agent memory files (`agent-memory/<role>.md`).
  Those are user-authored as patterns emerge during reviews. Only `shared.md`
  is seeded.

## Hard rules

1. **Evidence-grounded only.** Every entry in `memory.md` and `agent-memory/shared.md`
   MUST trace to a real file or convention in THIS repo. No generic advice.
2. **Surgical writes.** Skip artifacts that don't apply. A repo with no
   non-obvious build steps does NOT need `.kit/workflows/build.md` --
   omit it. A library with no shared types may not need a memory entry on
   schema patterns.
3. **Size budgets**:
   - `memory.md`: **<=40 entries** (kit convention -- enforced by post-session
     compress). Aim for the highest-leverage facts.
   - `agent-memory/shared.md`: **<=200 lines**.
   - `.kit/workflows/{name}.md`: **<=150 lines** each.
   - `workflow-briefs/*.md`: **under 5000 tokens each**.
   - Use bullets. No essays.
4. **Coverage report at the end.** List facts you considered but didn't
   record (with reason: too obvious, not stable enough, etc.). User decides
   gaps.
5. **Idempotent re-run.** If `.kit/` exists, AUDIT each file: surgical
   updates only, ask before regenerating.

## Output structure

```text
.kit/
|-- context/
|   |-- memory.md            # durable repo architectural facts (<=40 entries)
|   |-- handoffs.md          # cross-session shared handoff index (header only at init)
|   |-- history.md           # historical decision log (header only at init)
|   |-- reflections.md       # workflow improvement candidates (empty at init)
|   |-- agent-memory/
|   |   `-- shared.md        # cross-role specialist guidance
|   `-- workflow-briefs/
|       |-- workflow-explorer.md
|       |-- workflow-implementer.md
|       |-- workflow-reviewer.md
|       |-- workflow-skeptic.md
|       |-- workflow-ui-qa.md
|       `-- prompt-synthesizer.md
`-- workflows/
    |-- shared.md            # repo-specific notes shared across all workflows (only if non-trivial)
    |-- build.md             # repo-specific /build overrides (only if needed)
    `-- review.md            # repo-specific /review overrides (only if needed)
```


## What goes in each file

### `.kit/context/memory.md` -- durable architectural facts

Highest-leverage. Read by every `/build`, `/plan`, `/review` session. Each
entry is a fact a future agent should know without re-deriving from the
codebase.

**Good entries**:
- "Auth uses JWT in `Authorization: Bearer` header; verified by `auth_middleware.py:42`. Tokens are 1-hour TTL; refresh via `/api/auth/refresh`."
- "Database migrations live in `migrations/` and run via `alembic upgrade head`. Never edit a migration after merge -- create a new one."
- "Frontend dev server: `cd apps/frontend && npm run dev` (Vite, port 5173). Backend: `uvicorn backend.main:app --reload` (port 8000)."
- "Schema source-of-truth: `packages/types/`. Never re-declare interfaces or Zod schemas elsewhere -- always `import` from there."

**Bad entries** (skip these):
- "Uses Node.js" (obvious from package.json)
- "Has tests" (obvious)
- Anything that belongs in inline source comments
- Speculation ("might use Redis later")

Format each entry with:
- a one-line fact
- a `cite:` line pointing at the file:line that proves it
- optional `why:` line for non-obvious rationale

### `.kit/context/handoffs.md` -- cross-session shared index

At init: just write the canonical header so post-session.ps1 knows where
to append. Do NOT seed any handoff content.

```markdown
# Cross-Session Handoff Index

Append-only. One row per shared session tag emitted by post-session.ps1.

| Date       | Session ID                  | Task                          | Summary                          |
|------------|----------------------------|-------------------------------|----------------------------------|
```

### `.kit/context/history.md` -- decision log header

```markdown
# Repo History

Architectural decisions, deprecations, and learnings worth keeping.
Auto-aged by compress-memory.ps1: entries older than 90 days move to
history.archive.md.
```

Empty body at init.

### `.kit/context/reflections.md` -- workflow improvements

Empty file with header. Populated by `/reflect` skill.

```markdown
# Workflow Reflections

Suggested workflow improvements. Promoted entries are deleted (not
annotated). 5+ unaddressed entries gates the next session via
reflect-trigger.ps1.
```

### `.kit/context/agent-memory/shared.md` -- cross-role guidance

Patterns / conventions that apply to ALL specialist sub-agents working in
this repo. Embedded in subagent prompts via `specialist-memory-resolver.ps1`.

Examples grounded in repo evidence:
- "Error handling: never `except: pass`. Always log + re-raise or convert
  to a typed error. See `core/errors.py` for the typed-error hierarchy."
- "Tests live in `tests/` mirroring source layout. Use `pytest.fixture` for
  shared setup. Never inline-mock the DB -- use the fixture in `tests/conftest.py`."
- "Imports: absolute, never relative. Lint enforces this via ruff."

Skip if the repo has no non-obvious cross-role patterns. Many repos don't
need this file.

### `.kit/context/workflow-briefs/*.md` -- role-specific workflow preload

Write compact briefs that each core workflow agent reads before acting. These
are narrower than `memory.md`: they answer "what should this role know before
touching this repo?" without making every agent read every repo document.

Files to write:
- `workflow-explorer.md`: codebase map, search entry points, high-signal files,
  useful commands, known traps.
- `workflow-implementer.md`: architecture preferences, file placement,
  reusable components/APIs/utilities, implementation conventions, required
  verification, "do not do" rules.
- `workflow-reviewer.md`: review priorities, contract boundaries, test
  expectations, docs/wiki sync rules, historical problem areas.
- `workflow-skeptic.md`: fragile areas, hidden failure modes,
  rollback/migration risks, scope-drift traps.
- `workflow-ui-qa.md`: primary flows, routes/screens, UI defaults,
  accessibility/responsive expectations, browser/test commands.
- `prompt-synthesizer.md`: non-negotiable constraints, file boundaries,
  user-facing terminology, verification language.

Rules:
- each file under 5000 tokens
- bullets only; no essays
- cite repo evidence as `path:line`
- no implementation bodies
- write "No stable repo-specific guidance found yet." when a section has no
  grounded facts yet

### `.kit/workflows/*.md` -- repo-specific workflow overrides

Only write these when the kit's global skill needs repo-specific augmentation:

- `shared.md`: notes that apply to multiple workflows (test command, deploy gate, etc.)
- `build.md`: repo-specific `/build` policy (extra verification commands, extra reviewers, file guards)
- `review.md`: repo-specific `/review` policy (mandatory review categories, severity overrides, extra audit checks)

If a repo doesn't have non-obvious workflow rules, OMIT these files entirely.

## Workflow

### Step 0 -- git archaeology first

Before writing anything, run the `git-archaeology` workflow (or follow its
sequence manually) when the repo has enough commit history. Use the resulting
Project Conventions Profile as evidence for:

- naming conventions
- directory and file placement norms
- test layout patterns
- preferred UI / backend structure
- class vs function usage patterns
- stable architecture rules shown repeatedly in real commits

If history is sparse, state that clearly and fall back to current-code evidence.

### Step 1 -- repo type detection

Same as `wiki-init`: detect language, framework, monorepo layout.

### Step 2 -- harvest durable facts

Walk the repo for facts that meet ALL of:
- Stable (would still be true in 6 months)
- Non-obvious (not derivable from package.json / pyproject.toml in 30s)
- Load-bearing (a future agent making a wrong assumption here would cause real harm)

Sources to check:
- Auth / session / token handling files
- Schema source files (Zod schemas, SQLAlchemy models, GraphQL SDL)
- Migration directories + run command
- Test conventions (`tests/` layout, fixture patterns)
- Build / deploy commands not in `npm scripts`
- Trust boundary definitions (where untrusted input enters)
- Module boundary contracts (what crosses which package edge)
- Git-backed conventions from `git-archaeology` that are stable enough to
  guide future coding (directory organization, UI composition, API-call
  boundaries, function/class style)

Cap at 40 entries. Pick the 40 most-load-bearing.

### Step 3 -- write `.kit/context/memory.md`

Use the format above. Cite file:line for every entry.

### Step 4 -- seed handoffs.md / history.md / reflections.md

Headers only. Empty bodies.

### Step 5 -- write `agent-memory/shared.md`

Only if you can find >=3 cross-role patterns from real evidence. Otherwise skip.
This is the right place for git-backed implementation conventions that
specialists should follow during coding and review:

- UI component composition norms
- backend boundary rules
- file / directory placement rules
- preferred function / class patterns
- API call / data-access placement rules

### Step 6 -- write `workflow-briefs/*.md`

Create `.kit/context/workflow-briefs/` and write the six role briefs listed
above. Synthesize from `memory.md`, `conventions.md`, `agent-memory/shared.md`,
`.wiki/*` when present, git-archaeology output, and current code evidence.
These briefs are mandatory for bootstrapped repos even when some sections say
"No stable repo-specific guidance found yet."

### Step 7 -- write `.kit/workflows/*.md` overrides

Only if the kit's global skills need augmentation. For most repos, the
global skills are sufficient -- skip these.

### Step 8 -- recommend `/derive-repo-skills`

If the repo has stable internal conventions worth turning into repo-local
skills (architectural style, naming patterns, layering rules, UI composition
rules), recommend the user run
`/derive-repo-skills` next. Do NOT run it automatically -- that's a
separate workflow with its own evidence requirements.

### Step 9 -- coverage report

```
## Coverage report
- 23 facts considered, 18 recorded, 5 skipped:
  - "uses TypeScript" -- too obvious (skipped)
  - "has Storybook" -- mentioned in package.json (skipped)
  - "auth flow may change Q3" -- not stable enough (skipped)
  - "uses Redis for caching" -- recorded with cite (kept)
  - ... (3 more)
- agent-memory/shared.md: written (4 cross-role patterns found)
- workflows/build.md: skipped (no non-obvious build rules)
- workflows/review.md: skipped (no repo-specific review policy)
```

## Re-run mode (existing .kit/)

If `.kit/` already exists:
1. Read every existing file.
2. Diff against current code: which entries are stale, missing, or no
   longer reflect reality?
3. Surgical updates only -- one entry at a time. Show diff before applying.
4. Never overwrite handoffs.md, history.md, or reflections.md (they're
   session-emitted; users own them).
5. If memory.md is over 40 entries, prompt the user to identify the
   stalest ones for removal -- don't auto-prune.

## Anti-patterns

- **Generic templates** ("Auth: uses JWT") -- worthless without citations.
- **Aspirational entries** ("Will migrate to Postgres later") -- skip until done.
- **Duplicating package.json** -- if it's in dependencies, skip.
- **Skipping the coverage report** -- the gaps are valuable signal.
- **Auto-running derive-repo-skills** -- separate workflow, separate evidence.

## Integration with other skills

- **`/build`**: core workflow agents read `.kit/context/workflow-briefs/<agent>.md`,
  then `.kit/context/memory.md` + handoffs.md + agent-memory/. After `/kit-init`,
  these resolve.
- **`/plan`**: same.
- **`/review`**: reads `.kit/context/reflections.md` + memory.md.
- **`/reflect`**: appends to reflections.md.
- **`pre-session.ps1`**: reports `KIT: MISSING` and recommends running this
  skill when `.kit/` is absent.
- **`derive-repo-skills`**: complementary -- run AFTER kit-init if repo
  conventions are stable enough to extract repo-local skills.
