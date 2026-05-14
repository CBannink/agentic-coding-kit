# /build — Kilo Code custom mode

When the user invokes `/build` (or asks to implement, fix, refactor):

1. Run `pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "<task>"`.
2. Read the brief it emits — scope, tier, swarm mode, prior handoffs.
3. Reuse approved `plan.md` if present. If not, drop back to /plan first.
4. Read `~/.agents/skills/build/SKILL.md` for the workflow phases.
5. Implement only the scoped change. Verify with fresh test output.
6. Run `pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>"` when done.

The verification gate is hard. No completion claims without fresh evidence.
