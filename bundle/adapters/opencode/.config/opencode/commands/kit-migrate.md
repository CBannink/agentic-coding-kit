# /kit-migrate

Convert this repo from existing legacy agentic conventions (gstack agents/,
hand_off.md, memory/MEMORY.md, project-scoped .claude/agents/, etc.) to
coexist with the kit. Idempotent + non-destructive: archives, never deletes.

Read and follow `~/.claude/skills/kit-migrate/SKILL.md` exactly:

1. **Detect** existing pipeline files (handoffs, memory, agents, plans, project-scoped settings).
2. **Classify** each: MAP (migrate to kit equivalent), ARCHIVE (move to `.kit/legacy/`), KEEP (repo wins; don't touch), MERGE (ask user).
3. **Ensure `.kit/` exists** (run `/kit-init` first if missing).
4. **Execute MAP operations**: filtered append from `memory/MEMORY.md` to `.kit/context/memory.md`; index-entry append from `agents/handoffs/latest.md` to `.kit/context/handoffs.md`; specialist memory migration for active `agents/<role>.md` files.
5. **Execute ARCHIVE moves** via `git mv` to preserve history. Never `rm`.
6. **Skip KEEP files** -- log them in coverage report. Specifically:
   - `.claude/agents/`, `.claude/commands/`, `.claude/settings.json` (project-scoped, repo wins)
   - `.cursor/`, `.cursorrules`, `.aider.conf.yml`
   - `.github/copilot-instructions.md`, `.kilocode/rules/`
   - Repo's CLAUDE.md / AGENTS.md (already augmented via include marker by install)
7. **Surface MERGE conflicts** to user; never auto-resolve.
8. **Coverage report**: detected / mapped / archived / kept / skipped per file.

Hard rules: idempotent, evidence-grounded, repo wins on `.claude/agents/` +
`.claude/commands/` + project settings, never `rm` user data, ask before
destructive operations.

This is the third bootstrap skill, parallel to `/wiki-init` (greenfield wiki)
and `/kit-init` (greenfield kit memory). `/kit-migrate` is for repos that
ALREADY have a pipeline you want to coexist with.

If `.kit/legacy/` already exists from a prior run, AUDIT mode: re-detect
patterns, skip already-migrated files, re-emit coverage report so user sees
current state. Never re-archive or re-merge.
