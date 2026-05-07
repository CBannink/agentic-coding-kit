---
name: wiki-init
description: Bootstraps the .wiki/ directory for a repo that doesn't have one. Surveys active code plus recent git history (entry points, routers, public exports, services, scheduled jobs, UI routes, conventions), identifies major sections, and writes per-section docs plus architecture.md, codebase.md, features.md, and .features rollups. Use when .wiki/ is missing, when /build / /plan / /review reports the wiki rule isn't satisfied, or when the user says "we don't have docs" / "bootstrap the wiki" / "set up .wiki".
---

# Wiki Init Skill

Bootstrap the `.wiki/` directory from REAL code evidence in this repo.
Per-section docs save re-exploration on every `/build`, `/review`, and
`/plan` session and serve as the user-visible-feature contract for design
loops (`/redesign`, `playwright-explorer`, `ux-driver`, `ui-driver`).

## When to run

- `.wiki/` does not exist in the repo
- `pre-session.ps1` emitted `WIKI: MISSING` in the BRIEF block
- `/build` step 10 has no wiki to update
- User asks to "bootstrap the wiki", "set up .wiki", "we don't have docs",
  "document this repo properly"
- A `/redesign` would benefit from a documented feature contract before
  taking screenshots

## Hard rules

1. **Evidence-grounded only.** Every section page, every feature entry,
   every "interacts with" arrow MUST trace to a real file in THIS repo. No
   generic templates. If you can't cite the file, don't write the line.
2. **Surgical writes.** Skip sections that don't apply. Don't invent UI
   sections in a backend-only repo. Don't invent CLI features in a library.
3. **One file per section.** Don't merge unrelated concerns into one
   "core" page. Don't fragment one concern across many pages.
4. **Coverage report at the end.** List the source files / dirs you did
   NOT cover in any section page. The user decides whether each is
   intentional or a gap.
5. **Size budget (anti-bloat).** Hard limits per file:
   - `index.md`: **≤100 lines**. Just an entry point — no narrative.
   - `sections/<name>.md`: **≤150 lines** (target 80-120). Past 150,
     split or move detail into linked source comments.
   - `architecture.md`: **≤200 lines**.
   - `codebase.md`: **≤200 lines**.
   - `features.md`: **≤300 lines**. Past that, split by category into
     `features/<category>.md` and keep `features.md` as the index.
   - Per "Non-obvious notes" subsection: **≤10 bullets**, drop stalest
     when adding.
   These are LOAD-BEARING. Wiki bloat defeats the purpose -- if a section
   page costs more context to read than just grepping the source, the
   wiki has failed.

## Lazy-load contract (how skills consume the wiki)

The wiki is NEVER bulk-loaded. Skills consume it via the resolver:

```powershell
pwsh ~/.agents/tools/wiki-resolver.ps1 -Task "<short task description>" -ChangedFiles "<comma-sep list>" -RepoRoot .
```

The resolver returns a JSON object listing only the section pages whose
"Key files" overlap with the changed-file set OR whose name appears in
the task description. It also always includes `index.md`, `architecture.md`,
and `codebase.md` when present. Skills embed only those returned pages in
subagent prompts -- they do NOT pass the whole `.wiki/sections/` tree.

If the resolver returns nothing, skills proceed without wiki context (it
wasn't relevant for this task). That's the desired behavior, not a failure.

## Output structure

```
.wiki/
├── index.md             # canonical entry point: lists sections + links architecture + codebase + features
├── codebase.md          # where important code lives + git-backed conventions profile
├── features.md          # user-visible features rollup (human)
├── .features            # machine-readable feature ID list
├── architecture.md      # cross-section overview, dependency arrows
└── sections/
    ├── <section-1>.md   # one page per major section
    ├── <section-2>.md
    └── ...
```

## Per-section page template

Use this skeleton for every `sections/<name>.md`. Skip subsections that
don't apply. Never invent content to fill them.

```markdown
# Section: <name>

## Purpose
<one paragraph -- what this section does for the system>

## Key files
- `<path/to/file.ext>` -- <one-line role>
- `<path/to/dir/>` -- <one-line role>

## Inputs (what calls into this section)
- <caller / event / route> via `<file>`

## Outputs (what this section produces)
- <produced artifact / response / side effect> via `<file>`

## Interacts with
- `sections/<other>.md` -- <one-line interaction>

## Non-obvious notes
<only if applicable -- gotchas, invariants, performance constraints,
historical context not visible in the code itself>
```

## Workflow

### Step 0 -- git archaeology first

Before writing the wiki, run the `git-archaeology` workflow (or follow its
sequence manually) when the repo has enough history. Use the resulting
Project Conventions Profile to document how the codebase actually tends to be
structured: file placement, naming, test layout, UI composition patterns,
backend layering, class-vs-function preferences, and other repeatable norms.

If the repo has too little history, say so and fall back to current-code
evidence only.

### Step 1 -- repo type detection

Detect the primary language(s) and framework(s):
- `package.json` present? Read `dependencies` + `devDependencies` + `scripts.dev` to identify Node framework (Next, Vite, Express, NestJS, etc.).
- `pyproject.toml` / `setup.py` / `requirements.txt`? Read for Python framework (FastAPI, Django, Flask, Click, Typer).
- `Cargo.toml`? Rust binary or library.
- `go.mod`? Go module.
- Mixed monorepo? Identify `packages/` or `apps/` boundaries.

### Step 2 -- entry-point discovery

By language:

**Node**:
- `package.json` `main`, `bin`, `exports` fields
- Framework configs: `next.config.*`, `vite.config.*`, `nuxt.config.*`
- App dirs: `app/`, `pages/`, `src/app/`, `src/pages/`
- Route files: anything matching `**/route.{ts,js}` or framework-specific patterns

**Python**:
- `pyproject.toml` `[project.scripts]` / `[project.entry-points]`
- `__main__.py` files
- Framework apps: `fastapi.FastAPI()` instantiation, `django` `urls.py`, Flask `app = Flask()`

**Routes / handlers**:
- `routes/`, `controllers/`, `handlers/`, `endpoints/` directories
- Annotation-based: search for `@app.get`, `@router.post`, `@Controller`, etc.

**Scheduled jobs / queues**:
- `cron`, `scheduler`, `worker`, `queue` directories or files
- Decorators: `@scheduled`, `@cron`, `@task`

### Step 3 -- section identification

Group files into MAJOR sections by concern. Bias toward fewer, larger
sections (5-10 total) over many tiny ones. Examples:

For a typical web app:
- `auth` (login, sessions, tokens, middleware)
- `api` (HTTP routes / controllers)
- `data` (models, schemas, repositories, migrations)
- `services` (business logic that's not in routes or models)
- `ui` (frontend components, pages — only if applicable)
- `jobs` (background workers, schedulers — only if applicable)
- `infra` (config, bootstrap, DI container, observability)

For a CLI tool:
- `commands` (each subcommand grouped)
- `core` (the underlying engine the commands wrap)
- `io` (file system, network, external API adapters)
- `config` (config loading, validation)

For a library:
- One section per major public API surface (e.g., `query`, `mutate`,
  `subscribe` for a DB client). NOT one section per file.

**Rule of thumb**: if two areas would have nearly-identical "interacts
with" lines, merge them. If a section page would be < 80 words, merge or
delete it.

### Step 4 -- write each section page

For each identified section, follow the template above. Cite real files
only. Note interactions with other sections by reading actual imports /
calls. If you write "auth interacts with api", confirm by grepping
`api/` for imports of `auth/`.

### Step 5 -- write architecture.md

Top-down overview. One short paragraph per layer (e.g., "User → API →
Service → Data"). Then a section-dependency table:

```markdown
| Section | Depends on | Depended on by |
|---|---|---|
| auth | data | api, services |
| api | auth, services | (none -- entry layer) |
...
```

Plus a "Boundaries" section listing what crosses module boundaries (e.g.,
"`api/` is the only section that talks to the HTTP layer; `auth/` is the
only section that knows about JWT secrets").

Also include an **Architecture principles** section covering the stable coding
rules a new implementer must follow, grounded in current code plus git
history: UI composition patterns, API/backend boundaries, data-access rules,
shared contract movement, and preferred abstractions.

### Step 5b -- write codebase.md

`codebase.md` is the advanced coder's map of where important things live and
how code is normally shaped in this repo. It should answer:

- where the major surfaces live (UI, API, services, data, jobs, tests)
- how directories are organized
- what naming conventions are normal
- how long functions tend to be
- whether the repo prefers fewer larger functions or more extracted helpers
- whether classes, hooks, services, or plain functions are the normal pattern
- how UI talks to APIs / backend / data layer
- which files are the primary entry points to read first

Ground this in both code evidence and git-backed conventions. Keep it concise
and navigational.

### Step 6 -- write features.md (user-visible rollup)

Survey the active code for user-visible capabilities:
- CLI subcommands (each one is a feature)
- HTTP routes (group related routes by resource: e.g., "Profile CRUD")
- UI pages / screens (each a feature)
- Scheduled / cron behaviors visible to the user (e.g., "nightly export")
- Public exports (for libraries)
- Configuration switches that change observable behavior

Group by category. For each feature: one-line description + entry point
(file path + line, route URL, or CLI command). Format example:

```markdown
## CLI Commands
- `incogniton profile list` -- show all browser profiles. Entry: `cli/cmd/profile.py:42`.
- `incogniton proxy import <file>` -- bulk import proxies from CSV/Excel. Entry: `cli/cmd/proxy.py:88`.

## HTTP API
- `GET /api/profiles` -- list profiles for the authenticated user. Route: `api/profiles.ts:12`.

## UI Pages
- Profile dashboard at `/profiles`. Component: `app/profiles/page.tsx`.
```

### Step 7 -- write .features

One feature ID per line, organized by category with comment headers.
Format:

```
# CLI Commands
cli/profile-list
cli/profile-create
cli/proxy-import

# HTTP API
api/profiles-list
api/profiles-create

# UI Pages
ui/profiles-dashboard
```

### Step 7b -- write index.md (canonical entry point)

The first file a new contributor / agent reads. Tight, navigational only.
No narrative. Template:

```markdown
# <Repo name> -- Wiki Index

One-paragraph what-is-this. Mention the primary language / framework and
the production purpose (one sentence each).

## Sections (per code area)

- [`auth`](sections/auth.md) -- one-line summary
- [`api`](sections/api.md) -- one-line summary
- [`data`](sections/data.md) -- one-line summary
- ... (one bullet per `.wiki/sections/*.md`, in dependency order)

## Cross-cutting

- [`architecture.md`](architecture.md) -- system overview + section dependency table
- [`codebase.md`](codebase.md) -- where major code lives + coding conventions profile
- [`features.md`](features.md) -- user-visible features rollup
- [`.features`](.features) -- machine-readable feature ID list

## How agents use this wiki

Skills do not bulk-load the wiki. They use the lazy-load resolver:
```
pwsh ~/.agents/tools/wiki-resolver.ps1 -Task "<desc>" -ChangedFiles "<list>" -RepoRoot .
```
The resolver always loads `index.md`, `architecture.md`, and `codebase.md`
when they exist, plus only the sections whose `Key files` overlap with the
changed-file set. Update them surgically when their files change -- do not let
pages drift.

## Last updated
<YYYY-MM-DD by /wiki-init>
```

Order the section bullets by dependency depth from `architecture.md`:
foundational layers (data, auth, infra) first; entry layers (api, ui) last.
Keep one-line summaries to one short sentence -- the section page itself
has the detail.

### Step 8 -- coverage report

After writing all section pages, list files / directories you did NOT cover.
The user decides:

```
## Coverage gaps (review and decide)
- `tools/internal/codegen/` -- internal-only, intentionally undocumented?
- `legacy/v1-shim.ts` -- candidate for deletion?
- `experiments/` -- skip until promoted to a real section?
```

## Anti-patterns to avoid

- **Generic templates** ("This is the auth module. It handles
  authentication.") -- worthless. Cite real files.
- **One section per file** -- defeats the purpose. Group by concern.
- **Inventing interactions** -- only list what you can verify by reading
  imports/calls.
- **Skipping the coverage report** -- the gaps are the most useful part.
- **Treating wiki-init as one-shot** -- the user reviews, asks for fixes,
  you re-run on specific sections.

## Integration with other skills

- **`/build`**: step 10 will UPDATE `.wiki/features.md` after wiki-init exists.
- **`/plan`**: reads section pages plus `architecture.md` / `codebase.md` to load context without re-exploration.
- **`/review`**: cross-references findings to section pages and architecture/codebase principles, flags drift.
- **`/redesign` / `playwright-explorer`**: read `features.md` for UI flows
  to test.
- **`pre-session.ps1`**: reports `WIKI: MISSING` and recommends running this
  skill when `.wiki/` is absent.

## Re-running on an existing wiki

If `.wiki/` already exists, do NOT overwrite. Instead:
1. Read every existing section page.
2. Diff against current code: which sections are stale, missing, or no
   longer reflect reality?
3. Surgical updates only -- one section at a time. Show the diff before
   applying.
4. If a section is truly out of date and a surgical update isn't enough,
   ask the user before regenerating it.

The wiki is durable repo memory. Treat it as such.
