# /kit-init

Bootstrap (or audit) the `.kit/` directory for this repo from real code evidence.

Read and follow `~/.claude/skills/kit-init/SKILL.md` exactly:

1. Detect repo type / framework.
2. Harvest durable facts (stable, non-obvious, load-bearing).
3. Write `.kit/context/memory.md` (≤40 entries with file:line citations).
4. Seed `.kit/context/handoffs.md`, `history.md`, `reflections.md` (headers only).
5. Write `.kit/context/agent-memory/shared.md` only if ≥3 cross-role patterns found.
6. Write `.kit/workflows/{shared,build,review}.md` ONLY if the kit's
   global skills need repo-specific augmentation. Otherwise skip.
7. Recommend `/derive-repo-skills` next (separate workflow, do NOT auto-run).
8. Emit a coverage report listing facts considered but skipped.

Hard rules: evidence-grounded only (every entry traces to a real file),
size budgets enforced (memory.md ≤40 entries, agent-memory/shared.md
≤200 lines, workflows files ≤150 lines each), no generic templates, no
aspirational entries.

If `.kit/` already exists, AUDIT instead of overwrite -- diff entries
against current code, surgically update stale ones, ask before regenerating.
Never touch `handoffs.md` / `history.md` / `reflections.md` content (those
are session-emitted; users own them).

This is for `.kit/` ONLY. For the user-visible feature wiki, use `/wiki-init`.
For repo-local skill routing (`.kit/skills/index.json`), run
`/derive-repo-skills` AFTER this.
