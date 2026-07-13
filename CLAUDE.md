# Agentic Coding Kit — Claude Code

Follow the repository instructions in `AGENTS.md`. The active Claude Code
session is the main orchestrator; do not delegate the session to an
orchestrator subagent.

Use `/build`, `/design`, `/analyze`, `/review`, `/pr-ready`, `/threat-model`,
and `/wiki`. Skills contain the reusable loops, canonical agents provide
bounded roles, and every agent handoff returns to this main session for routing.

Edit canonical sources under `core/` and `packs/`, not generated `adapters/`.
Run the fresh validation commands documented in `AGENTS.md` after relevant
changes.
