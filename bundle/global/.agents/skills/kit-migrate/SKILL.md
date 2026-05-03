---
name: kit-migrate
description: Converts a repo with existing legacy agentic pipeline (gstack agents/, hand_off.md, memory/MEMORY.md, project-scoped .claude/agents/, etc.) to coexist with the kit's .kit/ tree and conventions. Detects existing files, maps them to kit equivalents, archives obsoleted files, preserves repo conventions where they win. Use when /kit-init or /wiki-init reports the repo already has a pipeline that conflicts, or when the user says "migrate this repo to the kit" / "install the kit on top of existing setup".
---

# Kit Migrate Skill

Convert a repo from legacy agentic conventions (gstack, ECC, custom
hand_off.md, etc.) to coexist with the kit. Parallel to `/kit-init` and
`/wiki-init` -- those bootstrap greenfield; this one converges with
existing setup.

**Important**: per the kit's "REPO WINS" precedence rule, this skill
does NOT delete or override the repo's conventions. It MAPS legacy
pipeline files to kit equivalents (where the kit can read them via its
tools), ARCHIVES anything that's now obsolete (preserving git history),
and LEAVES ALONE anything that should keep working as-is.

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

1. **Idempotent**. Re-run is safe -- subsequent invocations either no-op
   or surgical-update. Never destructive on re-run.
2. **Preserve git history**. Use `git mv` for any file moves. Never
   `rm` user data; archive instead.
3. **Repo wins**. If the repo has its own CLAUDE.md, agents/, commands/,
   plans/, .claude/settings.json -- KEEP THEM. The kit augments via
   skills/agents/commands/hooks; it does not replace what the repo
   already has working.
4. **Ask before destructive moves**. Any operation that could lose data
   (e.g., overwriting an existing `.kit/context/memory.md` with content
   from `memory/MEMORY.md`) requires user confirmation.
5. **Coverage report at the end**. Lists every detection, every action
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

### Project-scoped agents / commands (KEEP AS-IS, repo wins)
- `.claude/agents/<name>.md`
- `.claude/commands/<name>.md`
- `.claude/settings.json` (do NOT modify -- user's hook config)
- `.cursor/rules/`, `.cursorrules`
- `.aider.conf.yml`
- `.github/copilot-instructions.md`
- `.kilocode/rules/*.md`

### Repo CLAUDE.md / AGENTS.md
- KEEP AS-IS. The kit's `agentic-kit:include` block is already appended
  during install. Don't re-edit.

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

- **MAP** -- legacy file content should be migrated to a kit equivalent
  (e.g., `memory/MEMORY.md` -> `.kit/context/memory.md`)
- **ARCHIVE** -- legacy file is now obsolete; move to
  `.kit/legacy/<original-path>` to preserve history without confusion
- **KEEP** -- repo file should remain as-is (project agents, commands,
  settings.json, CLAUDE.md, .cursor/, etc.)
- **MERGE** -- both legacy and kit versions exist; need user input on
  how to reconcile

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
