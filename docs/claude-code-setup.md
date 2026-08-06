# Claude Code Setup

Claude Code is a first-class ACK host using native instructions, agents, skills,
settings, permissions, and worktrees. ACK does not add a parallel lifecycle or
session-memory runtime.

Build the CLI, then install only Claude:

```text
npm ci --prefix cli
npm run bundle --prefix cli
node cli/dist/kit.cjs install --host claude --scope user --profile core
```

For repository-local installation:

```text
node cli/dist/kit.cjs install --host claude --scope project --repo <path> --profile core
```

The installer manages:

- one Claude instruction surface (`CLAUDE.md`);
- native agents under `.claude/agents/` or the user equivalent;
- native skills under `.claude/skills/` or the user equivalent;
- only supported settings changes, with ownership and restoration data.

Invoke `/build`, `/design`, `/architecture`, `/grill`, `/analyze`, `/review`,
`/pr-ready`, `/threat-model`, `/wiki`, or `/experiment`. The active Claude
session remains the primary orchestrator and chooses INLINE or LOOP. Optional
specialist agents return to it; they do not create nested orchestration chains.

Use Claude's own model, effort, Advisor, permission, worktree, compaction, and
observability features where available. Keep provider-specific model choices
outside portable ACK prompts.
