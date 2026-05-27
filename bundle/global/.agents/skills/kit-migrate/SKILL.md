---
name: kit-migrate
description: Use to migrate an existing repo's agentic rules into the kit pattern while preserving repo build, test, style, and product preferences.
---

# Kit Migrate Skill

**Convergence operation, not coexist.** Bring a repo's local rules into
alignment with the kit's global conventions while preserving the repo's
domain-specific preferences.

Parallel to `/kit-init` (greenfield kit memory bootstrap) and `/wiki-init`
(greenfield wiki bootstrap). Where those bootstrap empty repos, this one
**converges** repos that already have legacy agentic conventions.

## What converges vs what stays

The kit has GLOBAL conventions for **structural** things — handoff
locations, memory routing, session state, lifecycle bookkeeping. Two
competing structural pipelines in one repo creates the silent-drop
problem we keep hitting empirically. After `/kit-migrate`, the repo's
structural conventions ALIGN with the kit's; competing instructions
get rewritten or removed.

The repo's **substantive** preferences stay untouched. These are
domain-specific decisions the kit can't make for you:
- Build / test / lint commands (`npm test` vs `pytest` vs `cargo test`)
- Deploy gates ("never push to main without CI green")
- Code style ("snake_case", "tests/ mirrors src/", "absolute imports only")
- Agent personas ("Scout", "Pricing Agent", custom builder/reviewer roles)
- Project-scoped `.claude/agents/`, `.claude/commands/`, `.claude/skills/`
  (CLI-native auto-discovery; kit doesn't compete with these)
- Other-CLI configs (`.cursor/`, `.aider.conf.yml`, `.github/copilot-instructions.md`)

**The litmus test**: if the rule is about *where state goes / how the
session is bookkept / how memory routes*, that's structural — it
converges. If the rule is about *what gets built / how it's tested /
who reviews it / the project's identity*, that's preference — it stays.

## When to run

- You just installed the kit globally and want it to coexist with this
  repo's existing pipeline
- `/kit-init` said the repo already has `.codex/` or `.kit/` or pipeline
  files and you want to consolidate
- `pre-session.ps1` reports DUAL-LAYER conflict (repo's CLAUDE.md
  references a pipeline that doesn't match kit conventions)
- User asks to "migrate this repo to the kit" / "set this repo up for
  the kit" / "install kit on top of legacy"

## Hard rules

1. **Idempotent**. Re-run is safe — subsequent invocations either no-op
   or surgical-update. Never destructive on re-run.
2. **Preserve git history**. Use `git mv` for any file moves. Never
   `rm` user data; archive instead.
3. **Convergence on STRUCTURE, preservation on PREFERENCE.** Local
   structural rules (handoff path, memory routing, session state) get
   migrated into kit pattern. Local preferences (build commands, code
   style, agent personas, project-scoped `.claude/agents/`) stay
   untouched. The litmus test above is load-bearing.
4. **CLAUDE.md surgical edits with diff preview**. If the repo's
   CLAUDE.md has structural rules that compete with the kit (e.g.,
   "write handoff to agents/handoffs/latest.md, NEVER use external
   session-state directories"), show a diff of the proposed edit
   BEFORE applying. Default is: ask. The agentic-kit:include block
   appended by the installer is separate; this is about the user's
   own content.
5. **Ask before content migration that has merge conflicts**. If a
   target file (e.g., `.kit/context/memory.md`) already has content
   AND the legacy file has content, surface the diff and ask. Never
   auto-merge memory.
6. **Coverage report at the end**. Lists every detection, every action
   taken, every action skipped (with reason). User decides any unclear
   cases.

## Detection patterns

Source-of-truth file patterns this skill recognizes:

### Legacy handoff conventions
- `hand_off.md` / `HANDOFFS.md` / `HANDOFF.md` (root-level)
- `agents/handoffs/latest.md` / `agents/handoffs/chain-log.md` (gstack-style)
- `agents/session_state.md` (gstack-style orchestrator state)
- `.handoffs/` (custom dir)
- `docs/handoffs/`

### Legacy memory conventions
- `memory/MEMORY.md` (gstack-style)
- `memory/skills.md`
- `memory/<role>_kb.md` (e.g., `pricing_kb.md`, `crawler_kb.md`)
- `MEMORY.md` (root-level)
- `.memory/` (custom dir)
- Existing `.codex/context/` or `.kit/context/` from earlier kit install

### Legacy plans / specs
- `.claude/plans/` (Claude Code project-scoped plans)
- `docs/plans/`, `plans/`
- `.codex/specs/` or `.kit/specs/`

### Project-scoped agents / commands (KEEP — local preferences)
- `.claude/agents/<name>.md` — CLI-native auto-discovery, project's workforce
- `.claude/commands/<name>.md` — CLI-native auto-mounted commands
- `.claude/settings.json` — user's hook config; never modify
- `.claude/skills/<name>/` — project-scoped skills
- `.cursor/rules/`, `.cursorrules`
- `.aider.conf.yml`
- `.github/copilot-instructions.md`
- `.kilocode/rules/*.md`

### Repo CLAUDE.md / AGENTS.md (SURGICAL EDITS, with diff preview)
- The agentic-kit:include block (added by installer) is the kit's territory.
- The user's own content gets a STRUCTURAL audit:
  - Identify lines that mandate competing pipeline behavior (handoff path,
    memory location, session state, lifecycle bookkeeping).
  - Show the user a diff of proposed surgical edits to those lines (drop
    them or rewrite to align with kit pattern).
  - Preserve everything else: build commands, project context, agent
    persona descriptions, code style rules, deploy gates, repo-specific
    conventions.
- DEFAULT: ask before applying. Diff must be visible.

## Workflow

### Step 1 -- repo conventions audit

Walk the repo and detect which legacy pipeline files exist. Output a
table:

```
| Pattern              | Path                         | Status   |
|----------------------|------------------------------|----------|
| hand_off.md          | ./hand_off.md                | found    |
| agents/handoffs      | ./agents/handoffs/           | found    |
| memory/MEMORY.md     | ./memory/MEMORY.md           | found    |
| project agents       | ./.claude/agents/ (5 files)  | found    |
| .kit/                | (none)                       | missing  |
| .wiki/               | (none)                       | missing  |
```

### Step 2 -- decision tree

For each detection, classify:

- **MIGRATE** -- legacy file is a STRUCTURAL competitor; content gets
  migrated into a kit equivalent + original archived
  (e.g., `memory/MEMORY.md` -> `.kit/context/memory.md` + archive)
- **ARCHIVE-ONLY** -- legacy file is structural but has no useful
  content to migrate; just `git mv` to `.kit/legacy/`
- **KEEP** -- local preference, repo-owned (project agents, commands,
  settings.json, .cursor/, etc.) — touch nothing
- **REWRITE** -- repo's own CLAUDE.md / AGENTS.md content has lines
  mandating competing pipeline behavior; surgical edit with diff preview,
  ask user before applying
- **MERGE** -- both legacy and kit versions of same artifact have
  meaningful content; ask user how to reconcile, never auto-merge

### Step 2b -- CLAUDE.md / AGENTS.md structural scan (the convergence step)

Read the repo's `CLAUDE.md` and `AGENTS.md`. Identify lines / sections
that mandate STRUCTURAL behavior conflicting with the kit. Examples of
what to flag for surgical removal/rewrite:

- "After every task, write your handoff to `agents/handoffs/latest.md`"
  → conflicts with kit's `~/.agents/session-state/{id}/handoffs.md`
- "Update `agents/session_state.md` after every step"
  → kit's session state is `~/.agents/session-state/{id}/state.json`
- "NEVER use external session-state directories"
  → directly competes with kit
- "Read `memory/MEMORY.md` for project memory"
  → kit reads `.kit/context/memory.md` via specialist-memory-resolver
- "Use builder → reviewer → pr chain in `.claude/agents/`"
  → KEEP IF the chain is local agents the kit doesn't compete with;
  REWRITE only if it explicitly forbids the kit's flow

Examples of what to PRESERVE (local preferences):

- "Tests live in `tests/` mirroring source layout. Use pytest"
- "Deploy via `git push origin main` (CI auto-deploys)"
- "Agent persona: Scout. Voice: friendly, concise"
- "Use snake_case throughout; lint config is the source of truth"
- "Customer LTV > €100; never spam"

For each REWRITE candidate, show the user a unified diff and ask:
```
PROPOSED CLAUDE.md edit:
@@ line 47-51 @@
-After every task, write your handoff to `agents/handoffs/latest.md` and
-append summary to `agents/handoffs/chain-log.md`. Do NOT use any
-session-state directories outside this repo. The repo pipeline is the
-source of truth.
+After every task, the kit writes a session handoff to
+`~/.agents/session-state/{id}/handoffs.md` (private per-session). The
+orchestrator should follow the kit's lifecycle scripts; sub-agents do
+not self-register.

Apply? [y/n]
```

Default = ask. Never auto-apply rewrites without diff.

### Step 3 -- ensure .kit/ exists

If `.kit/` doesn't exist, run `/kit-init` workflow first (greenfield
bootstrap), THEN proceed with mapping. If it does exist, check whether
its files were authored by `/kit-init` or are stale from an earlier
install -- ask user before overwriting.

### Step 4 -- execute MAP operations

For each MAP-classified file:

**`memory/MEMORY.md` -> `.kit/context/memory.md`**:
- Read existing kit memory.md (may have content from /kit-init)
- Read legacy memory/MEMORY.md
- Filter legacy entries: keep only those matching the kit's "non-obvious
  + load-bearing + cited" criteria. Drop generic entries ("uses Node.js")
  and aspirational entries ("will migrate to Postgres later").
- Append filtered entries to .kit/context/memory.md with a marker:
  ```
  ## Migrated from memory/MEMORY.md on YYYY-MM-DD
  - <entry 1> (cite: <original line>)
  - <entry 2>
  ```
- Cap total at 40 entries (kit convention enforced by compress-memory).

**`agents/handoffs/latest.md` -> `.kit/context/handoffs.md` index entry**:
- Read latest.md
- Append a one-line index entry to `.kit/context/handoffs.md` Session
  Handoff Index table with date, task slug, summary, and original path
- Move `agents/handoffs/latest.md` and `chain-log.md` to
  `.kit/legacy/agents/handoffs/` via `git mv` to preserve history

**`agents/<role>.md` -> `.kit/context/agent-memory/<role>.md`**:
- Only if recently modified (last 90 days) AND non-trivial content
- If matches `pricing.md`, `search_agent.md`, etc. -- migrate as
  specialist memory under matching role name
- Skip if file is generic gstack template stub (no real repo-specific facts)

**`agents/session_state.md` -> ARCHIVE**:
- Kit's session state lives at `~/.agents/session-state/`, not in repo
- `git mv agents/session_state.md .kit/legacy/agents/session_state.md`

### Step 5 -- ARCHIVE moves

For ARCHIVE-classified files, use `git mv <path> .kit/legacy/<path>`
to preserve git history. Add a one-line README in `.kit/legacy/`:

```markdown
# .kit/legacy/

Files moved here by /kit-migrate from this repo's previous agentic
pipeline. Kept for git history and rollback. Safe to delete after the
team confirms the kit's conventions are working.

Original locations preserved in the directory structure under this dir.
```

### Step 6 -- KEEP cases (do nothing)

For each KEEP-classified file, log it in the coverage report as
"preserved as-is (repo wins)". Don't touch:
- `.claude/agents/`, `.claude/commands/`, `.claude/settings.json`
- `.cursor/`, `.cursorrules`, `.aider.conf.yml`
- `.github/copilot-instructions.md`, `.kilocode/rules/`
- Repo's CLAUDE.md / AGENTS.md (already augmented via include marker
  by the install script)

### Step 7 -- MERGE cases (ask user)

If both legacy and kit versions of the same artifact exist with
non-trivial diverging content, surface the diff and ask:

```
MERGE NEEDED: memory/MEMORY.md and .kit/context/memory.md both have
content. Diff:
  + Legacy: 12 entries about pricing + crawler architecture
  + Kit:    8 entries from /kit-init (auth, schema, build commands)
Choose:
  [a] Append legacy to kit (keep both, deduplicate)
  [b] Replace kit with filtered legacy
  [c] Skip migration -- leave both as-is
  [d] Show diff line-by-line
```

Default: skip with note in coverage report -- never auto-resolve a MERGE.

### Step 8 -- coverage report

Final report covering:

```markdown
# /kit-migrate report -- YYYY-MM-DD

## Summary
- Detected: 8 legacy artifacts
- Mapped: 3 (memory.md content, handoffs index entry, 1 specialist memory)
- Archived: 2 (session_state.md, chain-log.md)
- Kept (repo wins): 6 (.claude/agents/, .claude/commands/, .claude/settings.json, CLAUDE.md, .cursor/rules/, .github/copilot-instructions.md)
- Merge cases skipped: 1 (memory.md -- user asked to defer)

## Actions taken
- git mv agents/session_state.md .kit/legacy/agents/session_state.md
- Appended 7 entries from memory/MEMORY.md to .kit/context/memory.md
- ...

## Recommendations
- Review .kit/context/memory.md -- migrated entries are tagged with
  source. Drop any that are now stale.
- Run /wiki-init next if .wiki/ doesn't exist (separate skill).
- Run pre-session.ps1 to verify the kit is now wired correctly.

## Skipped (need user decision)
- ...
```

## Re-run mode

If `/kit-migrate` runs again:
1. Re-detect legacy patterns -- some may have been added since last run
2. Skip files already moved to `.kit/legacy/` (already migrated)
3. Skip MAPs already applied (check for migration markers in target files)
4. Re-emit coverage report so the user sees current state

Never re-archive an already-archived file. Never re-append already-merged
content.

## Anti-patterns

- **Don't auto-resolve MERGE cases** -- always ask. Memory consolidation
  is irreversible without git history.
- **Don't touch project-scoped `.claude/agents/`** -- those are the user's
  custom workforce. Repo wins, kit doesn't compete.
- **Don't edit repo's CLAUDE.md content** -- the install script already
  appends the kit's `agentic-kit:include` block. Anything else stays.
- **Don't rm anything** -- always `git mv` to `.kit/legacy/` for history.
- **Don't migrate generic content** -- if `memory/MEMORY.md` has
  "uses TypeScript" entries, drop them. Migrate only non-obvious + cited.
- **Don't promise feature parity** -- the kit ALSO doesn't run the user's
  custom builder/reviewer/pricing-agent chain from `.claude/agents/`.
  That keeps working in their preferred pipeline. The kit's hooks add
  enforcement around it, not replacement of it.

## Cross-CLI applicability

This skill is auto-discovered at `~/.claude/skills/kit-migrate/` and
`~/.config/opencode/skills/kit-migrate/`. It works the same regardless
of which CLI invokes it -- the migration is repo-level, not CLI-level.

For Codex CLI / Copilot CLI / Kilo Code users (which don't auto-discover
skills), the skill body can be copy-pasted into a fresh agent prompt
manually.

## Integration with other skills

- **Run BEFORE `/kit-init`** if you want a single bootstrap-and-migrate
  pass. Or run `/kit-init` first then `/kit-migrate` if you prefer
  separate steps.
- **Run AFTER `/wiki-init`** if you want the wiki up first; legacy
  doc/plan files can then be migrated to wiki sections via
  `/kit-migrate`.
- **Doesn't replace `/derive-repo-skills`** -- that's for generating
  repo-local skill routing from evidence. Run it AFTER /kit-migrate
  if you want repo-local skill index.
