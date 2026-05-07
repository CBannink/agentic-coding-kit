# /wiki-init

Bootstrap (or audit) the `.wiki/` directory for this repo from real code evidence.

Read and follow `__SKILL_ROOT__/wiki-init/SKILL.md` exactly:

1. Detect repo type / framework.
2. Run `/git-archaeology` first when the repo has enough history and use the conventions profile as evidence.
3. Discover entry points (CLI, routes, scheduled jobs, public exports, UI pages).
4. Identify 5-10 major sections by concern (not one per file).
5. For each section, write `.wiki/sections/<name>.md` per the template
   (purpose / key files / inputs / outputs / interacts-with / non-obvious notes).
6. Write `.wiki/architecture.md` with cross-section dependency table and architecture principles.
7. Write `.wiki/codebase.md` with where important code lives and git-backed coding conventions.
8. Write `.wiki/features.md` (user-visible feature rollup) and `.wiki/.features` (machine-readable IDs).
9. Write `.wiki/index.md` (canonical entry point -- links to sections, architecture, codebase, features; <=100 lines).
10. Emit a coverage report listing files NOT covered.

Hard rules: evidence-grounded only (every line traces to a real file),
size budgets enforced (index <=100, sections <=150, architecture <=200,
features <=300), no generic templates.

If `.wiki/` already exists, AUDIT instead of overwrite -- diff sections
against current code, surgically update stale ones, ask before regenerating.
