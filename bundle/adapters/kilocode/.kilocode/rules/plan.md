# /plan — Kilo Code custom mode

When the user invokes `/plan` (or asks to plan, scope, or pressure-test a
non-trivial change), follow the kit's plan workflow:

1. Read `.kit/workflows/plan.md` (repo override) if it exists.
2. Read `~/.agents/skills/plan/SKILL.md` for the global workflow.
3. Read `.kit/context/memory.md` and the Session Handoff Index.
4. Clarify scope, map files, trace blast radius, pressure-test the approach.
5. Stop for explicit approval before any code change.

Do NOT implement. Output a concrete plan; wait for approval. Use
`pwsh ~/.agents/tools/run-packet.ps1` to record the approved plan summary.
