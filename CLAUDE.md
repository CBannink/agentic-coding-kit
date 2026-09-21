# Agentic Coding Kit — Claude Code

Follow the repository instructions in `AGENTS.md`. The active Claude Code
session is the main orchestrator; do not delegate the session to an
orchestrator subagent.

Use `/analyze`, `/async`, `/backend`, `/build`, `/components`, `/debug`, `/design`, `/deslop`,
`/frontend`, `/grill`, `/migrate`, `/perf`, `/pr-ready`, `/python`, `/review`, `/security`, `/test`, `/threat-model`, `/typescript`, and `/wiki`. Skills contain the
reusable INLINE and LOOP playbooks, canonical agents provide bounded roles, and
every agent handoff returns to this main session for integration and routing.

Edit canonical sources under `core/` and `packs/`, not generated `adapters/`.
Run the fresh validation commands documented in `AGENTS.md` after relevant
changes.
